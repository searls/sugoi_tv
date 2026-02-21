import SwiftUI

// MARK: - Permission error detection

extension String {
  /// Matches common AVFoundation error messages for HTTP 403 / expired-token failures.
  var looksLikePermissionError: Bool {
    let lowered = lowercased()
    return lowered.contains("permission")
        || lowered.contains("authorized")
        || lowered.contains("forbidden")
        || lowered.contains("403")
  }
}

// MARK: - Shared playback controller

@MainActor @Observable
final class ChannelPlaybackController {
  let playerManager = PlayerManager()
  let channelListVM: ChannelListViewModel
  private(set) var selectedChannel: ChannelDTO?
  /// ID of the currently-playing VOD program, or nil when playing live.
  private(set) var playingProgramID: String?
  /// Metadata for the stream currently loading, shown in the loading overlay.
  private(set) var loadingTitle: String = ""
  @ObservationIgnored var persistence = PlaybackPersistence()

  /// Sidebar drill-down path: empty = channel list, [channel] = program list for that channel.
  var sidebarPath: [ChannelDTO] = []

  /// Cached program list ViewModels keyed by channel ID.
  /// Persists across navigation so returning to a channel is instant.
  private var programListVMs: [String: ProgramListViewModel] = [:]

  /// One-shot guard: allows a single reauth attempt per stream load.
  /// Reset to false in playChannel(), set to true after attempting reauth.
  private(set) var hasAttemptedReauth = false

  /// On compact layouts (iPhone), which column the NavigationSplitView should show.
  /// Starts at `.sidebar` so the channel list appears first; switches to `.detail` on play.
  var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

  /// Local HTTP proxy that injects Referer headers for AirPlay compatibility.
  /// When ready, stream URLs route through this proxy so the Apple TV can
  /// reach the VMS server without needing custom HTTP headers.
  private(set) var refererProxy: RefererProxy?

  private let provider: any TVProvider

  init(appState: AppState) {
    self.provider = appState.activeProvider
    self.channelListVM = ChannelListViewModel(
      provider: appState.activeProvider
    )
    if let referer = appState.vmsReferer {
      let proxy = RefererProxy(referer: referer)
      proxy.start()
      self.refererProxy = proxy
    }

    // Populate sidebar from cache immediately (no network)
    channelListVM.loadCachedChannels()
  }

  /// Select a channel from cached data. Returns immediately.
  func selectFromCache() {
    autoSelectChannel()
  }

  /// Fetch fresh channels from network and re-check selection if needed.
  func refreshChannelList() async {
    await channelListVM.loadChannels()
    let allChannels = channelListVM.channelGroups.flatMap(\.channels)
    if selectedChannel == nil || !allChannels.contains(where: { $0.id == selectedChannel?.id }) {
      autoSelectChannel()
    }
  }

  func loadAndAutoSelect() async {
    selectFromCache()
    await refreshChannelList()
  }

  /// Pick a channel from whatever is currently in channelGroups.
  /// Prefers the last-played channel, then first live, then first overall.
  /// Sets selectedChannel but stays on the channel list (no drill-in or auto-play).
  private func autoSelectChannel() {
    let allChannels = channelListVM.channelGroups.flatMap(\.channels)
    guard !allChannels.isEmpty else { return }
    if !persistence.lastChannelId.isEmpty,
       let match = allChannels.first(where: { $0.id == persistence.lastChannelId }) {
      selectedChannel = match
    } else if let live = allChannels.first(where: { $0.running == 1 }) {
      selectedChannel = live
    } else {
      selectedChannel = allChannels.first
    }
  }

  /// Whether tapping the player detail area should collapse the sidebar.
  /// Returns false during AirPlay to avoid layout changes that interrupt external playback.
  var shouldCollapseSidebarOnTap: Bool {
    !playerManager.isExternalPlaybackActive
  }

  func playChannel(_ channel: ChannelDTO) {
    hasAttemptedReauth = false
    preferredCompactColumn = .detail
    guard let request = provider.liveStreamRequest(for: channel) else { return }

    playingProgramID = nil
    loadingTitle = channel.name
    persistence.recordLivePlay(channelId: channel.id)

    let (streamURL, referer) = resolveStreamURL(request)
    playerManager.loadLiveStream(url: streamURL, referer: referer)
    playerManager.setNowPlayingInfo(title: channel.name, isLiveStream: true)
  }

  /// Return the cached ProgramListViewModel, or create a new one for the given channel.
  /// Resets pagination on previously-viewed channels to keep the List lightweight.
  func programListViewModel(for channel: ChannelDTO) -> ProgramListViewModel {
    // Reset pagination on other channels so stale deep-scroll state doesn't persist
    for (id, vm) in programListVMs where id != channel.id {
      vm.resetPastDisplay()
    }
    if let existing = programListVMs[channel.id] {
      return existing
    }
    let vm = ProgramListViewModel(
      provider: provider,
      channelID: channel.id,
      channelName: channel.displayName
    )
    programListVMs[channel.id] = vm
    return vm
  }

  func playVOD(program: ProgramDTO, channelName: String, resumeFrom: TimeInterval = 0) {
    guard program.hasVOD else { return }
    hasAttemptedReauth = false
    preferredCompactColumn = .detail
    guard let request = provider.vodStreamRequest(for: program) else { return }

    playingProgramID = program.id
    loadingTitle = program.title
    persistence.recordVODPlay(programPath: program.path, title: program.title, channelName: channelName)

    let (streamURL, referer) = resolveStreamURL(request)
    playerManager.loadVODStream(url: streamURL, referer: referer, resumeFrom: resumeFrom)
    playerManager.setNowPlayingInfo(title: "\(channelName) - \(program.title)", isLiveStream: false)
  }

  // MARK: - Stream URL resolution

  /// Route through the local referer proxy when available (enables AirPlay),
  /// otherwise return the direct URL with the referer header for AVURLAsset injection.
  private func resolveStreamURL(_ request: StreamRequest) -> (url: URL, referer: String) {
    if request.requiresProxy, let proxy = refererProxy, let proxiedURL = proxy.proxiedURL(for: request.url) {
      return (proxiedURL, "")
    }
    return (request.url, request.headers["Referer"] ?? "")
  }

  // MARK: - Navigation

  /// Drill into a channel's program list. Optionally auto-play the live stream.
  func drillIntoChannel(_ channel: ChannelDTO, autoPlay: Bool) {
    sidebarPath = [channel]
    selectedChannel = channel
    persistence.lastChannelId = channel.id
    if autoPlay {
      playChannel(channel)
    }
  }

  /// Navigate back to the channel list. Optionally stop playback (compact layouts).
  func navigateBack(stopPlayback: Bool) {
    sidebarPath = []
    if stopPlayback {
      playerManager.stop()
    }
  }

  /// Attempt to handle a permission failure. Returns true if reauth should proceed,
  /// false if already attempted.
  func handlePermissionFailure() -> Bool {
    guard !hasAttemptedReauth else { return false }
    hasAttemptedReauth = true
    playerManager.clearError()
    return true
  }

  /// Test-only setter for hasAttemptedReauth.
  internal func setHasAttemptedReauthForTesting(_ value: Bool) {
    hasAttemptedReauth = value
  }

  /// Test-only setter for selectedChannel.
  internal func setSelectedChannelForTesting(_ channel: ChannelDTO?) {
    selectedChannel = channel
  }

  // MARK: - Persistence helpers

  /// Save the current VOD position if a VOD is playing.
  func saveVODPositionIfNeeded() {
    if playingProgramID != nil {
      persistence.savePosition(playerManager.currentTime)
    }
  }

  // MARK: - Playback controls

  /// Toggle play/pause on the current player.
  func togglePlayPause() {
    guard playerManager.player != nil else { return }
    playerManager.togglePlayPause()
  }

  /// Try to start playback from the current cached selection.
  /// No-op if already playing, on compact, or no selection available.
  func attemptLaunchPlayback(isCompact: Bool, lastActiveTimestamp: TimeInterval) {
    guard !isCompact,
          playerManager.state == .idle,
          sidebarPath.isEmpty,
          let channel = selectedChannel else { return }
    let decision = LaunchPlayback.decide(
      isCompact: isCompact,
      lastActiveTimestamp: lastActiveTimestamp,
      now: Date().timeIntervalSince1970,
      lastProgramID: persistence.lastPlayingProgramID,
      lastProgramTitle: persistence.lastPlayingProgramTitle,
      lastChannelName: persistence.lastPlayingChannelName,
      lastVODPosition: persistence.lastVODPosition
    )
    switch decision {
    case .resumeVOD(let id, let title, let name, let pos):
      sidebarPath = [channel]
      let program = ProgramDTO(time: 0, title: title, path: id)
      playVOD(program: program, channelName: name, resumeFrom: pos)
    case .playLive:
      playChannel(channel)
    case .doNothing:
      break
    }
  }

  /// Replay the current stream using the current session's access token.
  /// Call after reauthentication to rebuild stream URLs with fresh credentials.
  func replayCurrentStream() {
    if playingProgramID != nil, !persistence.lastPlayingProgramID.isEmpty {
      // Prefer live player position (mid-stream expiry) over persisted
      // position (load failure before playback started)
      let position = playerManager.currentTime > 0 ? playerManager.currentTime : persistence.lastVODPosition
      let program = ProgramDTO(time: 0, title: persistence.lastPlayingProgramTitle, path: persistence.lastPlayingProgramID)
      playVOD(program: program, channelName: persistence.lastPlayingChannelName, resumeFrom: position)
    } else if let channel = sidebarPath.last ?? selectedChannel {
      playChannel(channel)
    }
  }
}
