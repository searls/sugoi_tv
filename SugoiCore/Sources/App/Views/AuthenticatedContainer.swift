import SwiftUI

// MARK: - Unified authenticated container

/// 2-column NavigationSplitView for all platforms:
/// sidebar = channel list, detail = program list + player.
///
/// On regular (Mac/iPad): detail is an HStack showing programs and player side by side.
/// On compact (iPhone): detail is a NavigationStack pushing from programs → player.
struct AuthenticatedContainer: View {
  let appState: AppState
  @State private var controller: ChannelPlaybackController
  @State private var columnVisibility: NavigationSplitViewVisibility = .all
  @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
  @AppStorage("sidebarVisible") private var sidebarVisible = true
  @AppStorage("lastActiveTimestamp") private var lastActiveTimestamp: Double = 0
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.horizontalSizeClass) private var sizeClass
  @FocusState private var sidebarFocused: Bool
  @FocusState private var channelListFocused: Bool
  @FocusState private var programListFocused: Bool
  @State private var channelListSelection: String?
  /// Drives the NavigationStack push to PlayerView on compact.
  @State private var showingPlayer = false
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
    NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $preferredCompactColumn) {
      sidebarContent
        .focused($sidebarFocused)
        .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 360)
    } detail: {
      detailColumn
    }
    .task {
      // Phase 1: Select from cache and start playback immediately
      controller.selectFromCache()
      if sizeClass == .regular {
        channelListSelection = controller.selectedChannel?.id
      }
      if controller.attemptLaunchPlayback(isCompact: sizeClass != .regular, lastActiveTimestamp: lastActiveTimestamp) {
        channelListSelection = controller.selectedChannel?.id
        showingPlayer = true
        preferredCompactColumn = .detail
      }
      focusChannelList()

      // Phase 2: Refresh channels from network (non-blocking for UI)
      await controller.refreshChannelList()

      // Phase 3: If cold start (no cache), try playing now that we have data
      if sizeClass == .regular {
        channelListSelection = controller.selectedChannel?.id
      }
      if controller.attemptLaunchPlayback(isCompact: sizeClass != .regular, lastActiveTimestamp: lastActiveTimestamp) {
        channelListSelection = controller.selectedChannel?.id
        showingPlayer = true
        preferredCompactColumn = .detail
      }
      focusChannelList()
    }
    .onAppear {
      let show = SidebarPersistence.shouldShowSidebar(
        wasSidebarVisible: sidebarVisible,
        lastActiveTimestamp: lastActiveTimestamp,
        now: Date().timeIntervalSince1970
      )
      sidebarVisible = show
      if sizeClass == .regular {
        columnVisibility = show ? .all : .detailOnly
      }
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
      if columnVisibility != .detailOnly {
        withAnimation { columnVisibility = .detailOnly }
        return .handled
      }
      return .ignored
    }
    .onKeyPress(.space) {
      guard controller.playerManager.player != nil else { return .ignored }
      controller.togglePlayPause()
      return .handled
    }
    .onChange(of: columnVisibility) { _, newValue in
      let visible = (newValue != .detailOnly)
      if visible != sidebarVisible {
        sidebarVisible = visible
        if visible {
          if controller.selectedChannel != nil {
            focusProgramList()
          } else {
            focusChannelList()
          }
        }
      }
    }
    .onChange(of: scenePhase) { _, newPhase in
      if newPhase == .background || newPhase == .inactive {
        lastActiveTimestamp = Date().timeIntervalSince1970
        controller.saveVODPositionIfNeeded()
      }
    }
    .onChange(of: appState.session?.accessToken) { _, _ in
      if let newSession = appState.session {
        controller.updateSession(newSession)
      }
    }
    .onChange(of: channelListSelection) { _, newID in
      guard let newID else { return }
      let channel = controller.channelListVM.channelGroups
        .flatMap(\.channels)
        .first { $0.id == newID }
      guard let channel, channel.id != controller.selectedChannel?.id else { return }
      controller.selectedChannel = channel
      // On regular, auto-play when selecting a new channel
      if sizeClass == .regular {
        controller.playChannel(channel)
      }
      // Reset player push when switching channels on compact
      showingPlayer = false
    }
    .onChange(of: controller.selectedChannel?.id) { _, newID in
      if sizeClass == .regular {
        channelListSelection = newID
      }
    }
    .onChange(of: controller.playerManager.state) { _, newState in
      if case .failed(let message) = newState,
         message.looksLikePermissionError,
         controller.handlePermissionFailure() {
        Task {
          let newSession = await appState.reauthenticate()
          if let newSession {
            controller.updateSession(newSession)
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

  private func focusChannelList() {
    channelListFocused = false
    Task { @MainActor in
      channelListFocused = true
    }
  }

  private func focusProgramList() {
    programListFocused = false
    Task { @MainActor in
      programListFocused = true
    }
  }

  // MARK: - Sidebar (channel list)

  private var sidebarContent: some View {
    VStack(spacing: 0) {
      channelListContent

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
    proxy.scrollTo(id, anchor: .center)
  }

  private var channelListList: some View {
    List(selection: $channelListSelection) {
      channelSections
    }
    .focused($channelListFocused)
    .onKeyPress(.return) {
      guard let channel = controller.selectedChannel else { return .ignored }
      if sizeClass == .regular {
        controller.playChannel(channel)
      }
      return .handled
    }
  }

  private var channelSections: some View {
    ForEach(controller.channelListVM.filteredGroups, id: \.category) { group in
      Section(group.category) {
        ForEach(group.channels) { channel in
          ChannelRow(
            channel: channel,
            thumbnailURL: StreamURLBuilder.thumbnailURL(
              channelListHost: controller.channelListVM.config.channelListHost,
              playpath: channel.playpath
            )
          )
          .tag(channel.id)
          .id(channel.id)
        }
      }
    }
  }

  // MARK: - Detail

  @ViewBuilder
  private var detailColumn: some View {
    if sizeClass == .regular {
      regularDetail
    } else {
      compactDetail
    }
  }

  /// Regular (Mac/iPad): programs and player side by side, like a 3-column layout.
  private var regularDetail: some View {
    HStack(spacing: 0) {
      if let channel = controller.selectedChannel {
        ProgramListView(
          viewModel: controller.programListViewModel(for: channel),
          playingProgramID: controller.playingProgramID,
          onPlayLive: {
            controller.playChannel(channel)
          },
          onPlayVOD: { program in
            controller.playVOD(program: program, channelName: channel.name)
          },
          focusBinding: $programListFocused
        )
        .navigationTitle(channel.displayName)
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
      }
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
        if columnVisibility != .detailOnly {
          withAnimation { columnVisibility = .detailOnly }
        }
      }
    }
  }

  /// Compact (iPhone): NavigationStack with program list as root, player pushed when playing.
  private var compactDetail: some View {
    NavigationStack {
      if let channel = controller.selectedChannel {
        ProgramListView(
          viewModel: controller.programListViewModel(for: channel),
          playingProgramID: controller.playingProgramID,
          onPlayLive: {
            controller.playChannel(channel)
            showingPlayer = true
          },
          onPlayVOD: { program in
            controller.playVOD(program: program, channelName: channel.name)
            showingPlayer = true
          },
          focusBinding: $programListFocused
        )
        .navigationTitle(channel.displayName)
        .navigationDestination(isPresented: $showingPlayer) {
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
          .ignoresSafeArea()
        }
      } else {
        ContentUnavailableView("Select a Channel", systemImage: "tv")
      }
    }
  }

  #if os(macOS)
  private var trafficLightGlassBacking: some View {
    Color.clear
      .frame(width: 74, height: 32)
      .glassEffect()
      .padding(.top, 10)
      .padding(.leading, 12)
  }
  #endif
}
