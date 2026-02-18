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
  var selectedChannel: ChannelDTO?
  /// ID of the currently-playing VOD program, or nil when playing live.
  var playingProgramID: String?
  /// Metadata for the stream currently loading, shown in the loading overlay.
  var loadingTitle: String = ""
  @ObservationIgnored @AppStorage("lastChannelId") var lastChannelId: String = ""
  @ObservationIgnored @AppStorage("lastPlayingProgramID") var lastPlayingProgramID: String = ""
  @ObservationIgnored @AppStorage("lastPlayingProgramTitle") var lastPlayingProgramTitle: String = ""
  @ObservationIgnored @AppStorage("lastPlayingChannelName") var lastPlayingChannelName: String = ""
  @ObservationIgnored @AppStorage("lastVODPosition") var lastVODPosition: Double = 0

  /// Sidebar drill-down path: empty = channel list, [channel] = program list for that channel.
  var sidebarPath: [ChannelDTO] = []

  /// Cached program list ViewModels keyed by channel ID.
  /// Persists across navigation so returning to a channel is instant.
  private var programListVMs: [String: ProgramListViewModel] = [:]

  var session: AuthService.Session
  /// One-shot guard: allows a single reauth attempt per stream load.
  /// Reset to false in playChannel(), set to true after attempting reauth.
  var hasAttemptedReauth = false

  /// On compact layouts (iPhone), which column the NavigationSplitView should show.
  /// Starts at `.sidebar` so the channel list appears first; switches to `.detail` on play.
  var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

  /// Local HTTP proxy that injects Referer headers for AirPlay compatibility.
  /// When ready, stream URLs route through this proxy so the Apple TV can
  /// reach the VMS server without needing custom HTTP headers.
  let refererProxy: RefererProxy

  private let programGuideService: ProgramGuideService

  init(appState: AppState, session: AuthService.Session) {
    self.session = session
    self.programGuideService = appState.programGuideService
    self.channelListVM = ChannelListViewModel(
      channelService: appState.channelService,
      config: session.productConfig
    )
    self.refererProxy = RefererProxy(referer: session.productConfig.vmsReferer)
    refererProxy.start()

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
    if !lastChannelId.isEmpty,
       let match = allChannels.first(where: { $0.id == lastChannelId }) {
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
    lastChannelId = channel.id
    preferredCompactColumn = .detail
    guard let url = StreamURLBuilder.liveStreamURL(
      liveHost: session.productConfig.liveHost,
      playpath: channel.playpath,
      accessToken: session.accessToken
    ) else { return }

    playingProgramID = nil
    loadingTitle = channel.name
    lastPlayingProgramID = ""
    lastPlayingProgramTitle = ""
    lastPlayingChannelName = ""
    lastVODPosition = 0

    // When the proxy is ready, route through it so AirPlay receivers can
    // reach the VMS server. Fall back to direct URL + AVURLAsset header
    // injection (works locally but not over AirPlay).
    if let proxiedURL = refererProxy.proxiedURL(for: url) {
      playerManager.loadLiveStream(url: proxiedURL, referer: "")
    } else {
      let referer = session.productConfig.vmsReferer
      playerManager.loadLiveStream(url: url, referer: referer)
    }
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
      programGuideService: programGuideService,
      config: session.productConfig,
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
    guard let url = StreamURLBuilder.vodStreamURL(
      recordHost: session.productConfig.recordHost,
      path: program.path,
      accessToken: session.accessToken
    ) else { return }

    playingProgramID = program.id
    loadingTitle = program.title
    lastPlayingProgramID = program.path
    lastPlayingProgramTitle = program.title
    lastPlayingChannelName = channelName

    if let proxiedURL = refererProxy.proxiedURL(for: url) {
      playerManager.loadVODStream(url: proxiedURL, referer: "", resumeFrom: resumeFrom)
    } else {
      let referer = session.productConfig.vmsReferer
      playerManager.loadVODStream(url: url, referer: referer, resumeFrom: resumeFrom)
    }
    playerManager.setNowPlayingInfo(title: "\(channelName) - \(program.title)", isLiveStream: false)
  }

  /// Replay the current stream using the current session's access token.
  /// Call after reauthentication to rebuild stream URLs with fresh credentials.
  func replayCurrentStream() {
    if playingProgramID != nil, !lastPlayingProgramID.isEmpty {
      // Prefer live player position (mid-stream expiry) over persisted
      // position (load failure before playback started)
      let position = playerManager.currentTime > 0 ? playerManager.currentTime : lastVODPosition
      let program = ProgramDTO(time: 0, title: lastPlayingProgramTitle, path: lastPlayingProgramID)
      playVOD(program: program, channelName: lastPlayingChannelName, resumeFrom: position)
    } else if let channel = sidebarPath.last ?? selectedChannel {
      playChannel(channel)
    }
  }
}
