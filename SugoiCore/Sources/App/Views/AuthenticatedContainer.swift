import SwiftUI

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
  @FocusState private var programListFocused: Bool
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
        if columnVisibility != .detailOnly {
          withAnimation { columnVisibility = .detailOnly }
        }
      }
    }
    .task {
      // Phase 1: Select from cache and start playback immediately
      controller.selectFromCache()
      controller.attemptLaunchPlayback(isCompact: sizeClass == .compact, lastActiveTimestamp: lastActiveTimestamp)
      focusChannelList()

      // Phase 2: Refresh channels from network (non-blocking for UI)
      await controller.refreshChannelList()

      // Phase 3: If cold start (no cache), try playing now that we have data
      controller.attemptLaunchPlayback(isCompact: sizeClass == .compact, lastActiveTimestamp: lastActiveTimestamp)
      focusChannelList()
    }
    .onAppear {
      let show = SidebarPersistence.shouldShowSidebar(
        wasSidebarVisible: sidebarVisible,
        lastActiveTimestamp: lastActiveTimestamp,
        now: Date().timeIntervalSince1970
      )
      sidebarVisible = show
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
        withAnimation { controller.navigateBack(stopPlayback: false) }
        return .handled
      } else if columnVisibility != .detailOnly {
        // Channel list → hide sidebar
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
          if controller.sidebarPath.isEmpty {
            focusChannelList()
          } else {
            focusProgramList()
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
    .onChange(of: controller.sidebarPath) { oldPath, newPath in
      if let channel = newPath.last, oldPath.last?.id != channel.id {
        // Framework-driven drill-in (NavigationStack push or swipe-back re-push).
        // Sync selection + persistence + auto-play via the controller method.
        let autoPlay = controller.selectedChannel?.id != channel.id && sizeClass != .compact
        controller.drillIntoChannel(channel, autoPlay: autoPlay)
      } else if newPath.isEmpty && !oldPath.isEmpty {
        // Navigated back to channel list (swipe-back on iOS)
        if sizeClass == .compact {
          controller.playerManager.stop()
        }
        focusChannelList()
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

  /// Focus the channel List directly — more reliable than the parent VStack's
  /// `.focused($sidebarFocused)` which doesn't propagate into NavigationSplitView
  /// sidebar columns after show/hide transitions.
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
    } else if sizeClass == .compact {
      ScrollViewReader { proxy in
        ChannelGridView(
          channelGroups: controller.channelListVM.filteredGroups,
          channelListHost: controller.channelListVM.config.channelListHost,
          onSelectChannel: { channel in
            channelSelection = channel.id
            withAnimation { controller.drillIntoChannel(channel, autoPlay: false) }
          }
        )
        .onAppear { scrollToSelected(proxy: proxy) }
        .onChange(of: controller.selectedChannel?.id) { _, _ in
          Task { @MainActor in
            await Task.yield()
            scrollToSelected(proxy: proxy)
          }
        }
      }
      .navigationTitle("Channels")
      .accessibilityIdentifier("channelList")
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
      withAnimation { controller.drillIntoChannel(channel, autoPlay: sizeClass != .compact) }
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
      channelSelection = channel.id
      withAnimation { controller.drillIntoChannel(channel, autoPlay: sizeClass != .compact) }
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
      },
      focusBinding: $programListFocused,
      onBack: {
        channelSelection = controller.selectedChannel?.id
        withAnimation { controller.navigateBack(stopPlayback: sizeClass == .compact) }
      },
      channelDescription: channel.displayDescription
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
