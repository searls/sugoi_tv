import AVFoundation
import Foundation
import MediaPlayer
import Observation

/// Playback state machine
public enum PlaybackState: Sendable, Equatable {
  case idle
  case loading
  case playing
  case paused
  case failed(String)
  case ended
}

/// Manages AVPlayer lifecycle with referer header injection
@MainActor
@Observable
public final class PlayerManager {
  public internal(set) var state: PlaybackState = .idle
  public private(set) var currentTime: TimeInterval = 0
  public private(set) var duration: TimeInterval = 0
  public private(set) var isLive: Bool = false
  public private(set) var isExternalPlaybackActive: Bool = false

  public var player: AVPlayer? { _player }

  @ObservationIgnored nonisolated(unsafe) private var _player: AVPlayer?
  @ObservationIgnored nonisolated(unsafe) private var timeObserver: Any?
  private var statusObservation: NSKeyValueObservation?
  private var rateObservation: NSKeyValueObservation?
  private var externalPlaybackObservation: NSKeyValueObservation?
  private var endOfPlaybackObserver: (any NSObjectProtocol)?
  private var lastStreamInfo: (url: URL, referer: String, isLive: Bool, resumeFrom: TimeInterval)?

  public init() {}

  // MARK: - Loading

  /// Load a live stream with referer header
  public func loadLiveStream(url: URL, referer: String) {
    lastStreamInfo = (url: url, referer: referer, isLive: true, resumeFrom: 0)
    let asset = makeAsset(url: url, referer: referer)
    loadAsset(asset, isLive: true)
  }

  /// Load a VOD stream with referer header and optional resume position
  public func loadVODStream(url: URL, referer: String, resumeFrom: TimeInterval = 0) {
    lastStreamInfo = (url: url, referer: referer, isLive: false, resumeFrom: resumeFrom)
    let asset = makeAsset(url: url, referer: referer)
    loadAsset(asset, isLive: false, resumeFrom: resumeFrom)
  }

  private func makeAsset(url: URL, referer: String) -> AVURLAsset {
    let options: [String: Any] = referer.isEmpty
      ? [:]
      : ["AVURLAssetHTTPHeaderFieldsKey": ["Referer": referer]]
    return AVURLAsset(url: url, options: options)
  }

  private func configureAudioSession() {
    #if os(iOS) || os(tvOS)
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(.playback, mode: .moviePlayback)
    try? session.setActive(true)
    #endif
  }

  private func loadAsset(_ asset: AVURLAsset, isLive: Bool, resumeFrom: TimeInterval = 0) {
    configureAudioSession()
    // When AirPlay is active and we already have a player, swap the item
    // instead of tearing down the player. Creating a new AVPlayer severs the
    // AirPlay route; replaceCurrentItem(with:) preserves it.
    // Pause first so the AirPlay XPC layer isn't mid-stream during the swap.
    if let existing = _player, isExternalPlaybackActive {
      existing.pause()
      cleanupObservations()
      self.isLive = isLive
      state = .loading

      let item = AVPlayerItem(asset: asset)
      existing.replaceCurrentItem(with: item)
      observePlayer(existing, resumeFrom: resumeFrom)
      existing.play()
      return
    }

    cleanup()
    self.isLive = isLive
    state = .loading

    let item = AVPlayerItem(asset: asset)
    let player = AVPlayer(playerItem: item)
    self._player = player

    observePlayer(player, resumeFrom: resumeFrom)
    player.play()
  }

  // MARK: - Controls

  public func play() {
    _player?.play()
    if _player != nil { state = .playing }
  }

  public func pause() {
    _player?.pause()
    if _player != nil { state = .paused }
  }

  public func togglePlayPause() {
    if state == .playing {
      pause()
    } else {
      play()
    }
  }

  public func seek(to time: TimeInterval) {
    guard !isLive else { return }
    let cmTime = CMTime(seconds: time, preferredTimescale: 600)
    _player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
  }

  public func skipForward(_ seconds: TimeInterval = 15) {
    seek(to: currentTime + seconds)
  }

  public func skipBackward(_ seconds: TimeInterval = 15) {
    seek(to: max(0, currentTime - seconds))
  }

  public func stop() {
    cleanup()
    lastStreamInfo = nil
    state = .idle
  }

  public func clearError() {
    if case .failed = state { state = .idle }
  }

  /// Re-create the player from the last-loaded stream. AVPlayer ignores play()
  /// on a failed AVPlayerItem, so we must build a fresh item to recover.
  public func retry() {
    guard case .failed = state, let info = lastStreamInfo else { return }
    let asset = makeAsset(url: info.url, referer: info.referer)
    loadAsset(asset, isLive: info.isLive, resumeFrom: info.resumeFrom)
  }

  // MARK: - Observation

  private func observePlayer(_ player: AVPlayer, resumeFrom: TimeInterval) {
    // Periodic time updates
    let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
    timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) {
      [weak self] time in
      MainActor.assumeIsolated {
        self?.currentTime = time.seconds
      }
    }

    // Player item status
    statusObservation = player.currentItem?.observe(\.status, options: [.new]) {
      [weak self] item, _ in
      Task { @MainActor in
        switch item.status {
        case .readyToPlay:
          self?.state = .playing
          self?.duration = item.duration.seconds.isFinite ? item.duration.seconds : 0
          if resumeFrom > 0 {
            self?.seek(to: resumeFrom)
          }
        case .failed:
          let message = item.error?.localizedDescription ?? "Unknown error"
          self?.state = .failed(message)
        default:
          break
        }
      }
    }

    // Rate changes (play/pause detection + live rate clamping)
    rateObservation = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
      Task { @MainActor in
        guard let self, self.state != .loading && self.state != .idle else { return }
        // Clamp playback speed to 1x for live streams
        if self.isLive && player.rate != 0 && player.rate != 1 {
          player.rate = 1.0
          return
        }
        if player.rate > 0 {
          self.state = .playing
        } else if self.state == .playing {
          self.state = .paused
        }
      }
    }

    // External playback (AirPlay) tracking
    externalPlaybackObservation = player.observe(\.isExternalPlaybackActive, options: [.new]) {
      [weak self] player, _ in
      Task { @MainActor in
        self?.isExternalPlaybackActive = player.isExternalPlaybackActive
      }
    }

    // End of playback notification (store token for proper removal)
    endOfPlaybackObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: player.currentItem,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.state = .ended
      }
    }
  }

  // MARK: - Now Playing

  /// Set Now Playing info for Lock Screen, Control Center, and AirPlay displays
  public func setNowPlayingInfo(title: String, isLiveStream: Bool) {
    var info: [String: Any] = [
      MPMediaItemPropertyTitle: title,
      MPNowPlayingInfoPropertyIsLiveStream: isLiveStream,
      MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
    ]
    if let item = _player?.currentItem {
      info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = item.currentTime().seconds
      if !isLiveStream && item.duration.seconds.isFinite {
        info[MPMediaItemPropertyPlaybackDuration] = item.duration.seconds
      }
    }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }

  // MARK: - Cleanup

  /// Tear down KVO observers and time observer without destroying the player.
  private func cleanupObservations() {
    if let observer = timeObserver, let player = _player {
      player.removeTimeObserver(observer)
    }
    timeObserver = nil
    statusObservation?.invalidate()
    statusObservation = nil
    rateObservation?.invalidate()
    rateObservation = nil
    externalPlaybackObservation?.invalidate()
    externalPlaybackObservation = nil
    if let observer = endOfPlaybackObserver {
      NotificationCenter.default.removeObserver(observer)
      endOfPlaybackObserver = nil
    }
    currentTime = 0
    duration = 0
  }

  private func cleanup() {
    cleanupObservations()

    _player?.pause()
    _player?.replaceCurrentItem(with: nil)
    _player = nil

    isLive = false
    isExternalPlaybackActive = false
  }

  /// Test-only: allows tests to simulate AirPlay state changes (via @testable import)
  internal func setExternalPlaybackActiveForTesting(_ active: Bool) {
    isExternalPlaybackActive = active
  }

  deinit {
    if let observer = timeObserver, let player = _player {
      player.removeTimeObserver(observer)
    }
    _player?.pause()
  }
}
