import SwiftUI

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
  @ObservationIgnored @AppStorage("lastChannelId") var lastChannelId: String = ""

  /// Sidebar drill-down path: empty = channel list, [channel] = program list for that channel.
  var sidebarPath: [ChannelDTO] = []

  /// Stable ViewModel for the currently-drilled-into channel's program list.
  /// Created once per channel navigation, persists across SwiftUI re-renders.
  var programListVM: ProgramListViewModel?

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

  func loadAndAutoSelect() async {
    // Auto-select from cache immediately if available
    autoSelectChannel()

    // Fetch fresh channels in background
    await channelListVM.loadChannels()

    // Re-check selection: update if we had no selection, or if the cached
    // channel disappeared from the fresh list
    let allChannels = channelListVM.channelGroups.flatMap(\.channels)
    if selectedChannel == nil || !allChannels.contains(where: { $0.id == selectedChannel?.id }) {
      autoSelectChannel()
    }
  }

  /// Pick a channel from whatever is currently in channelGroups.
  /// Prefers the last-played channel, then first live, then first overall.
  /// Also pushes into sidebarPath so the program list is visible.
  private func autoSelectChannel() {
    let allChannels = channelListVM.channelGroups.flatMap(\.channels)
    guard !allChannels.isEmpty else { return }
    let channel: ChannelDTO?
    if !lastChannelId.isEmpty,
       let match = allChannels.first(where: { $0.id == lastChannelId }) {
      channel = match
    } else if let live = allChannels.first(where: { $0.running == 1 }) {
      channel = live
    } else {
      channel = allChannels.first
    }
    if let channel {
      selectedChannel = channel
      withAnimation { sidebarPath = [channel] }
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
    if let existing = programListVM, existing.channelID == channel.id {
      return existing
    }
    let vm = ProgramListViewModel(
      programGuideService: programGuideService,
      config: session.productConfig,
      channelID: channel.id,
      channelName: channel.name
    )
    programListVM = vm
    return vm
  }

  func playVOD(program: ProgramDTO, channelName: String) {
    guard program.hasVOD else { return }
    hasAttemptedReauth = false
    preferredCompactColumn = .detail
    guard let url = StreamURLBuilder.vodStreamURL(
      recordHost: session.productConfig.recordHost,
      path: program.path,
      accessToken: session.accessToken
    ) else { return }

    if let proxiedURL = refererProxy.proxiedURL(for: url) {
      playerManager.loadVODStream(url: proxiedURL, referer: "")
    } else {
      let referer = session.productConfig.vmsReferer
      playerManager.loadVODStream(url: url, referer: referer)
    }
    playerManager.setNowPlayingInfo(title: "\(channelName) - \(program.title)", isLiveStream: false)
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
  #if os(macOS)
  @Environment(\.openSettings) private var openSettings
  // FB21962656: macOS NavigationStack sidebar bug — delete when resolved
  @State private var macChannelSelection: String?
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
        .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 360)
        // FB21962656: macOS NavigationStack sidebar bug — delete when resolved
        #if os(macOS)
        .toolbar {
          ToolbarItem(placement: .navigation) {
            if controller.sidebarPath.last != nil {
              Button {
                macChannelSelection = controller.selectedChannel?.id
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
        PlayerView(playerManager: controller.playerManager)
        #if os(macOS)
        if columnVisibility == .detailOnly {
          trafficLightGlassBacking
        }
        #endif
      }
      .ignoresSafeArea()
      #if os(macOS)
      .onTapGesture {
        guard controller.shouldCollapseSidebarOnTap else { return }
        if columnVisibility != .detailOnly {
          withAnimation {
            columnVisibility = .detailOnly
          }
        }
      }
      #endif
    }
    .task { await controller.loadAndAutoSelect() }
    .onAppear {
      let show = SidebarPersistence.shouldShowSidebar(
        wasSidebarVisible: sidebarVisible,
        lastActiveTimestamp: lastActiveTimestamp,
        now: Date().timeIntervalSince1970
      )
      columnVisibility = show ? .doubleColumn : .detailOnly
      lastActiveTimestamp = Date().timeIntervalSince1970
    }
    .onChange(of: columnVisibility) { _, newValue in
      sidebarVisible = (newValue != .detailOnly)
    }
    .onChange(of: scenePhase) { _, newPhase in
      if newPhase == .background || newPhase == .inactive {
        lastActiveTimestamp = Date().timeIntervalSince1970
      }
    }
    .onChange(of: appState.session?.accessToken) { _, _ in
      if let newSession = appState.session {
        controller.session = newSession
      }
    }
    .onChange(of: controller.sidebarPath) { oldPath, newPath in
      if let channel = newPath.last, oldPath.last?.id != channel.id {
        // Drilled into a new channel
        controller.selectedChannel = channel
        controller.lastChannelId = channel.id
        if sizeClass != .compact {
          // Mac/iPad: auto-play live when drilling into channel
          controller.playChannel(channel)
        }
      } else if newPath.isEmpty && !oldPath.isEmpty {
        // Navigated back to channel list
        controller.programListVM = nil
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
            if let channel = controller.sidebarPath.last {
              controller.playChannel(channel)
            }
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
    .onChange(of: macChannelSelection) { _, newSelection in
      guard let id = newSelection,
            let channel = controller.channelListVM.channelGroups
              .flatMap(\.channels).first(where: { $0.id == id })
      else { return }
      withAnimation { controller.sidebarPath = [channel] }
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
            if let id = controller.selectedChannel?.id {
              proxy.scrollTo(id, anchor: .center)
            }
          }
      }
      .listStyle(.sidebar)
      .accessibilityIdentifier("channelList")
    }
  }

  @ViewBuilder
  private var channelListList: some View {
    // FB21962656: macOS NavigationStack sidebar bug — delete when resolved
    #if os(macOS)
    List(selection: $macChannelSelection) {
      channelSections
    }
    #else
    List {
      channelSections
    }
    #endif
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

  @ViewBuilder
  private func channelItem(_ channel: ChannelDTO) -> some View {
    let row = ChannelRow(
      channel: channel,
      thumbnailURL: StreamURLBuilder.thumbnailURL(
        channelListHost: controller.channelListVM.config.channelListHost,
        playpath: channel.playpath
      )
    )
    // FB21962656: macOS NavigationStack sidebar bug — delete when resolved
    #if os(macOS)
    row.tag(channel.id)
    #else
    NavigationLink(value: channel) { row }
      .id(channel.id)
      .listRowBackground(
        controller.selectedChannel?.id == channel.id
          ? Color.accentColor.opacity(0.2)
          : nil
      )
    #endif
  }

  private func programListView(for channel: ChannelDTO) -> some View {
    ProgramListView(
      viewModel: controller.programListViewModel(for: channel),
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

