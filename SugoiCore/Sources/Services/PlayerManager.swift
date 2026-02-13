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

  public var player: AVPlayer? { _player }

  // nonisolated(unsafe) so deinit can clean up the time observer
  nonisolated(unsafe) private var _player: AVPlayer?
  nonisolated(unsafe) private var timeObserver: Any?
  private var statusObservation: NSKeyValueObservation?
  private var rateObservation: NSKeyValueObservation?
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
    let options = StreamURLBuilder.assetOptions(referer: referer)
    return AVURLAsset(url: url, options: options)
  }

  private func loadAsset(_ asset: AVURLAsset, isLive: Bool, resumeFrom: TimeInterval = 0) {
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
    let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
    timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) {
      [weak self] time in
      self?.currentTime = time.seconds
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

    // End of playback notification
    NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: player.currentItem,
      queue: .main
    ) { [weak self] _ in
      self?.state = .ended
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

  private func cleanup() {
    if let observer = timeObserver, let player = _player {
      player.removeTimeObserver(observer)
    }
    timeObserver = nil
    statusObservation?.invalidate()
    statusObservation = nil
    rateObservation?.invalidate()
    rateObservation = nil
    NotificationCenter.default.removeObserver(self)

    _player?.pause()
    _player?.replaceCurrentItem(with: nil)
    _player = nil

    currentTime = 0
    duration = 0
    isLive = false
  }

  deinit {
    if let observer = timeObserver, let player = _player {
      player.removeTimeObserver(observer)
    }
    _player?.pause()
  }
}
