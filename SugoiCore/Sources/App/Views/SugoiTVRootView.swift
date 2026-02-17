import SwiftUI

// MARK: - Sidebar toggle notification

public extension Notification.Name {
  static let toggleSidebar = Notification.Name("toggleSidebar")
}

public struct SugoiTVRootView: View {
  var appState: AppState

  public init(appState: AppState) {
    self.appState = appState
  }

  public var body: some View {
    Group {
      if appState.isRestoringSession {
        ProgressView("Restoring session…")
      } else if let session = appState.session {
        AuthenticatedContainer(appState: appState, session: session)
      } else {
        #if os(macOS)
        MacSignedOutPlaceholder()
        #else
        LoginView(
          viewModel: LoginViewModel(
            loginAction: { cid, password in
              try await appState.login(cid: cid, password: password)
            }
          )
        )
        #endif
      }
    }
    .task { await appState.restoreSession() }
  }
}

#if os(macOS)
/// Placeholder shown in the main window when not signed in on macOS.
/// Login lives in Settings (⌘,) so the user is directed there.
private struct MacSignedOutPlaceholder: View {
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    ContentUnavailableView {
      Label("Not Signed In", systemImage: "person.crop.circle.badge.questionmark")
    } description: {
      Text("Open Settings to sign in to your YoiTV account.")
    } actions: {
      Button("Open Settings…") {
        openSettings()
      }
      .buttonStyle(.borderedProminent)
      .keyboardShortcut(",", modifiers: .command)
    }
  }
}
#endif

#if DEBUG
#Preview { FixtureContainerPreview() }
#endif

// MARK: - Permission error detection

extension String {
  /// Matches common AVFoundation error messages for HTTP 403 / expired-token failures.
  var looksLikePermissionError: Bool {
    let lowered = localizedLowercase
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

  init(appState: AppState, session: AuthService.Session, defaults: UserDefaults = .standard) {
    self.session = session
    self.programGuideService = appState.programGuideService
    self.channelListVM = ChannelListViewModel(
      channelService: appState.channelService,
      config: session.productConfig,
      defaults: defaults
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
  func programListViewModel(for channel: ChannelDTO) -> ProgramListViewModel {
    if let existing = programListVMs[channel.id] {
      return existing
    }
    let vm = ProgramListViewModel(
      programGuideService: programGuideService,
      config: session.productConfig,
      channelID: channel.id,
      channelName: channel.name
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

// MARK: - Launch playback

/// Pure logic for deciding what to play on launch.
public enum LaunchPlayback {
  public enum Decision: Equatable {
    case doNothing
    case playLive
    case resumeVOD(programID: String, title: String, channelName: String, position: TimeInterval)
  }

  /// Decides what to auto-play when the app launches.
  /// - Parameters:
  ///   - isCompact: true on iPhone (compact horizontal size class)
  ///   - lastActiveTimestamp: seconds since 1970 of last activity (0 = first launch)
  ///   - now: current time in seconds since 1970
  ///   - lastProgramID: persisted VOD path, empty when last session was live
  ///   - lastProgramTitle: persisted VOD title
  ///   - lastChannelName: persisted channel name for the VOD
  ///   - lastVODPosition: persisted playback position in seconds
  ///   - staleThreshold: seconds of inactivity before session is considered stale (default 12h)
  public static func decide(
    isCompact: Bool,
    lastActiveTimestamp: TimeInterval,
    now: TimeInterval,
    lastProgramID: String,
    lastProgramTitle: String,
    lastChannelName: String,
    lastVODPosition: TimeInterval,
    staleThreshold: TimeInterval = 12 * 3600
  ) -> Decision {
    guard !isCompact else { return .doNothing }
    guard lastActiveTimestamp > 0 else { return .playLive } // first launch

    let elapsed = now - lastActiveTimestamp
    if elapsed >= staleThreshold { return .playLive }

    // Recent session with VOD in progress
    if !lastProgramID.isEmpty {
      return .resumeVOD(
        programID: lastProgramID,
        title: lastProgramTitle,
        channelName: lastChannelName,
        position: lastVODPosition
      )
    }

    return .playLive
  }
}

// MARK: - Sidebar persistence

/// Pure logic for deciding initial sidebar visibility on launch.
/// Defaults to open (doubleColumn) on first launch or after 12+ hours of inactivity.
public enum SidebarPersistence {
  /// Returns `true` when the sidebar should be visible (doubleColumn),
  /// `false` when it should be hidden (detailOnly).
  public static func shouldShowSidebar(
    wasSidebarVisible: Bool,
    lastActiveTimestamp: TimeInterval,
    now: TimeInterval,
    staleThreshold: TimeInterval = 12 * 3600
  ) -> Bool {
    guard lastActiveTimestamp > 0 else { return true } // first launch
    let elapsed = now - lastActiveTimestamp
    if elapsed >= staleThreshold { return true }
    return wasSidebarVisible
  }
}

// MARK: - Unified authenticated container

/// NavigationSplitView layout for all platforms: sidebar with channel list + program drill-down, detail with player.
/// On Mac and iPad, shows sidebar + detail side-by-side. On iPhone, collapses to push/pop stack.
struct AuthenticatedContainer: View {
  let appState: AppState
  @State private var controller: ChannelPlaybackController
  @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
  @AppStorage("sidebarVisible") private var sidebarVisible = true
  @AppStorage("lastActiveTimestamp") private var lastActiveTimestamp: Double = 0
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.horizontalSizeClass) private var sizeClass
  @FocusState private var sidebarFocused: Bool
  @FocusState private var channelListFocused: Bool
  @State private var channelSelection: String?
  #if os(macOS)
  @Environment(\.openSettings) private var openSettings
  #endif

  init(appState: AppState, session: AuthService.Session) {
    self.appState = appState
    self._controller = State(initialValue: ChannelPlaybackController(
      appState: appState, session: session
    ))
  }

  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $controller.preferredCompactColumn) {
      sidebarContent
        .focused($sidebarFocused)
        .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 360)
        // FB21962656: macOS NavigationStack sidebar bug — delete when resolved
        #if os(macOS)
        .toolbar {
          ToolbarItem(placement: .navigation) {
            if controller.sidebarPath.last != nil {
              Button {
                channelSelection = controller.selectedChannel?.id
                withAnimation { controller.sidebarPath = [] }
              } label: {
                Label("Channels", systemImage: "chevron.backward")
              }
            }
          }
        }
        #endif
    } detail: {
      ZStack(alignment: .topLeading) {
        PlayerView(
          playerManager: controller.playerManager,
          loadingTitle: controller.loadingTitle,
          loadingThumbnailURL: controller.selectedChannel.flatMap {
            StreamURLBuilder.thumbnailURL(
              channelListHost: controller.channelListVM.config.channelListHost,
              playpath: $0.playpath
            )
          }
        )
        #if os(macOS)
        if columnVisibility == .detailOnly {
          trafficLightGlassBacking
        }
        #endif
      }
      .ignoresSafeArea()
      .onTapGesture {
        guard controller.shouldCollapseSidebarOnTap else { return }
        if sidebarVisible {
          sidebarVisible = false
          withAnimation {
            columnVisibility = .detailOnly
          }
        }
      }
    }
    .task {
      // Phase 1: Select from cache and start playback immediately
      controller.selectFromCache()
      attemptLaunchPlayback()

      // Phase 2: Refresh channels from network (non-blocking for UI)
      await controller.refreshChannelList()

      // Phase 3: If cold start (no cache), try playing now that we have data
      attemptLaunchPlayback()
    }
    .onAppear {
      let show = SidebarPersistence.shouldShowSidebar(
        wasSidebarVisible: sidebarVisible,
        lastActiveTimestamp: lastActiveTimestamp,
        now: Date().timeIntervalSince1970
      )
      columnVisibility = show ? .doubleColumn : .detailOnly
      lastActiveTimestamp = Date().timeIntervalSince1970
    }
    .onKeyPress(.upArrow) {
      guard !sidebarFocused else { return .ignored }
      sidebarFocused = true
      return .handled
    }
    .onKeyPress(.downArrow) {
      guard !sidebarFocused else { return .ignored }
      sidebarFocused = true
      return .handled
    }
    .onKeyPress(.escape) {
      if !controller.sidebarPath.isEmpty {
        // Program list → back to channel list
        channelSelection = controller.selectedChannel?.id
        withAnimation { controller.sidebarPath = [] }
        // Don't set sidebarFocused here — channelListContent.onAppear handles it.
        // Setting it synchronously is a no-op (already true from program list focus)
        // and prevents the deferred transition in onAppear from firing.
        return .handled
      } else if sidebarVisible {
        // Channel list → hide sidebar
        sidebarVisible = false
        withAnimation { columnVisibility = .detailOnly }
        return .handled
      }
      return .ignored
    }
    .onKeyPress(.space) {
      guard controller.playerManager.player != nil else { return .ignored }
      controller.playerManager.togglePlayPause()
      return .handled
    }
    .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
      sidebarVisible.toggle()
      withAnimation {
        columnVisibility = sidebarVisible ? .doubleColumn : .detailOnly
      }
      if sidebarVisible {
        focusChannelList()
      }
    }
    .onChange(of: scenePhase) { _, newPhase in
      if newPhase == .background || newPhase == .inactive {
        lastActiveTimestamp = Date().timeIntervalSince1970
        if controller.playingProgramID != nil {
          controller.lastVODPosition = controller.playerManager.currentTime
        }
      }
    }
    .onChange(of: appState.session?.accessToken) { _, _ in
      if let newSession = appState.session {
        controller.session = newSession
      }
    }
    .onChange(of: controller.sidebarPath) { oldPath, newPath in
      if let channel = newPath.last, oldPath.last?.id != channel.id {
        // Drilled into a channel
        let isNewChannel = controller.selectedChannel?.id != channel.id
        controller.selectedChannel = channel
        controller.lastChannelId = channel.id
        if isNewChannel && sizeClass != .compact {
          // Mac/iPad: auto-play live when switching to a different channel
          controller.playChannel(channel)
        }
      } else if newPath.isEmpty && !oldPath.isEmpty {
        // Navigated back to channel list
        if sizeClass == .compact {
          controller.playerManager.stop()
        }
      }
    }
    .onChange(of: controller.playerManager.state) { _, newState in
      if case .failed(let message) = newState,
         message.looksLikePermissionError,
         !controller.hasAttemptedReauth {
        controller.hasAttemptedReauth = true
        controller.playerManager.clearError()
        Task {
          let newSession = await appState.reauthenticate()
          if let newSession {
            controller.session = newSession
            controller.replayCurrentStream()
          }
          #if os(macOS)
          if newSession == nil {
            openSettings()
          }
          #endif
        }
      }
    }
  }

  /// Try to start playback from the current cached selection.
  /// No-op if already playing or no selection available.
  private func attemptLaunchPlayback() {
    guard sizeClass != .compact,
          controller.playerManager.state == .idle,
          controller.sidebarPath.isEmpty,
          let channel = controller.selectedChannel else { return }
    let decision = LaunchPlayback.decide(
      isCompact: sizeClass == .compact,
      lastActiveTimestamp: lastActiveTimestamp,
      now: Date().timeIntervalSince1970,
      lastProgramID: controller.lastPlayingProgramID,
      lastProgramTitle: controller.lastPlayingProgramTitle,
      lastChannelName: controller.lastPlayingChannelName,
      lastVODPosition: controller.lastVODPosition
    )
    switch decision {
    case .resumeVOD(let id, let title, let name, let pos):
      controller.sidebarPath = [channel]
      let program = ProgramDTO(time: 0, title: title, path: id)
      controller.playVOD(program: program, channelName: name, resumeFrom: pos)
    case .playLive:
      controller.playChannel(channel)
    case .doNothing:
      break
    }
    focusChannelList()
  }

  /// Focus the channel List directly — more reliable than the parent VStack's
  /// `.focused($sidebarFocused)` which doesn't propagate into NavigationSplitView
  /// sidebar columns after show/hide transitions.
  private func focusChannelList() {
    channelListFocused = false
    Task { @MainActor in
      channelListFocused = true
    }
  }

  private var sidebarContent: some View {
    VStack(spacing: 0) {
      sidebarNavigation

      #if !os(macOS)
      Divider()
      Button("Sign Out") {
        Task { await appState.logout() }
      }
      .accessibilityIdentifier("signOutButton")
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
      #endif
    }
  }

  // MARK: Sidebar navigation

  private var sidebarNavigation: some View {
    // FB21962656: macOS NavigationStack sidebar bug — delete when resolved
    #if os(macOS)
    // NavigationStack in NavigationSplitView sidebar doesn't render pushed
    // destinations. Use List(selection:) to drive content swap instead.
    // Replace this block with the #else branch when fixed.
    Group {
      if let channel = controller.sidebarPath.last {
        programListView(for: channel)
          .transition(.push(from: .trailing))
      } else {
        channelListContent
          .transition(.push(from: .leading))
      }
    }
    #else
    NavigationStack(path: $controller.sidebarPath) {
      channelListRoot
    }
    #endif
  }


  // FB21962656: macOS NavigationStack sidebar bug — delete when resolved
  // (macOS uses List(selection:) content swap instead of NavigationStack push)
  #if !os(macOS)
  private var channelListRoot: some View {
    channelListContent
      .navigationDestination(for: ChannelDTO.self) { channel in
        programListView(for: channel)
      }
  }
  #endif

  @ViewBuilder
  private var channelListContent: some View {
    if controller.channelListVM.isLoading && controller.channelListVM.channelGroups.isEmpty {
      ProgressView("Loading channels...")
    } else if let error = controller.channelListVM.errorMessage, controller.channelListVM.channelGroups.isEmpty {
      ContentUnavailableView {
        Label("Error", systemImage: "exclamationmark.triangle")
      } description: {
        Text(error)
      } actions: {
        Button("Retry") { Task { await controller.channelListVM.loadChannels() } }
      }
    } else {
      ScrollViewReader { proxy in
        channelListList
          .onAppear {
            scrollToSelected(proxy: proxy)
            focusChannelList()
          }
          .onChange(of: controller.selectedChannel?.id) { _, _ in
            // Delay: selectedChannel changes in .task after onAppear;
            // the List needs a moment to settle before scrollTo works.
            Task { @MainActor in
              await Task.yield()
              scrollToSelected(proxy: proxy)
            }
          }
      }
      .listStyle(.sidebar)
      .accessibilityIdentifier("channelList")
    }
  }

  private func scrollToSelected(proxy: ScrollViewProxy) {
    guard let id = controller.selectedChannel?.id else { return }
    channelSelection = id
    proxy.scrollTo(id, anchor: .center)
  }

  private var channelListList: some View {
    List(selection: $channelSelection) {
      channelSections
    }
    .focused($channelListFocused)
    .onKeyPress(.return) {
      guard let id = channelSelection,
            let channel = controller.channelListVM.channelGroups
              .flatMap(\.channels).first(where: { $0.id == id })
      else { return .ignored }
      withAnimation { controller.sidebarPath = [channel] }
      return .handled
    }
  }

  private var channelSections: some View {
    ForEach(controller.channelListVM.filteredGroups, id: \.category) { group in
      Section(group.category) {
        ForEach(group.channels) { channel in
          channelItem(channel)
        }
      }
    }
  }

  private func channelItem(_ channel: ChannelDTO) -> some View {
    ChannelRow(
      channel: channel,
      thumbnailURL: StreamURLBuilder.thumbnailURL(
        channelListHost: controller.channelListVM.config.channelListHost,
        playpath: channel.playpath
      )
    )
    .tag(channel.id)
    .id(channel.id)
    .simultaneousGesture(TapGesture().onEnded {
      withAnimation { controller.sidebarPath = [channel] }
    })
    .listRowBackground(
      controller.selectedChannel?.id == channel.id
        ? Color.accentColor.opacity(0.2)
        : nil
    )
  }

  private func programListView(for channel: ChannelDTO) -> some View {
    ProgramListView(
      viewModel: controller.programListViewModel(for: channel),
      playingProgramID: controller.selectedChannel?.id == channel.id ? controller.playingProgramID : nil,
      onPlayLive: { controller.playChannel(channel) },
      onPlayVOD: { program in
        controller.playVOD(program: program, channelName: channel.name)
      }
    )
  }

  #if os(macOS)
  /// Liquid Glass capsule positioned behind the window's traffic light buttons.
  /// Placed in a ZStack with `.ignoresSafeArea()` so coordinates are relative to the window origin.
  private var trafficLightGlassBacking: some View {
    Color.clear
      .frame(width: 74, height: 32)
      .glassEffect()
      .padding(.top, 10)
      .padding(.leading, 12)
  }
  #endif
}

