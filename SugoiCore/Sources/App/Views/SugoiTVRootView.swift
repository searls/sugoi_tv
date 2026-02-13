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
        #if os(macOS)
        MacAuthenticatedContainer(appState: appState, session: session)
        #else
        AuthenticatedContainer(appState: appState, session: session)
        #endif
      } else {
        loginView
      }
    }
    .task { await appState.restoreSession() }
  }

  private var loginView: some View {
    LoginView(
      viewModel: LoginViewModel(
        loginAction: { cid, password in
          try await appState.login(cid: cid, password: password)
        }
      )
    )
  }
}

/// Video-first layout: player fills the window, channel guide slides in as a sidebar
private struct AuthenticatedContainer: View {
  let appState: AppState
  let session: AuthService.Session
  @State private var playerManager = PlayerManager()
  @State private var channelListVM: ChannelListViewModel
  @State private var selectedChannel: ChannelDTO?
  @State private var showingGuide = false
  @AppStorage("lastChannelId") private var lastChannelId: String = ""

  private let sidebarWidth: CGFloat = 340

  init(appState: AppState, session: AuthService.Session) {
    self.appState = appState
    self.session = session
    self._channelListVM = State(initialValue: ChannelListViewModel(
      channelService: appState.channelService,
      config: session.productConfig
    ))
  }

  var body: some View {
    ZStack(alignment: .topLeading) {
      PlayerView(playerManager: playerManager, isLive: playerManager.isLive)
        .allowsHitTesting(false)

      if showingGuide {
        // Dimming scrim behind sidebar
        Color.black.opacity(0.3)
          .onTapGesture { withAnimation { showingGuide = false } }

        sidebar
          .transition(.move(edge: .leading))
      }

      if !showingGuide {
        guideButton
      }
    }
    .ignoresSafeArea()
    .task {
      await channelListVM.loadChannels()
      autoSelectChannel()
    }
    .onChange(of: selectedChannel) { _, channel in
      if let channel {
        playChannel(channel)
      }
    }
  }

  private var guideButton: some View {
    Button {
      withAnimation { showingGuide = true }
    } label: {
      Image(systemName: "sidebar.leading")
        .font(.title)
    }
    .buttonStyle(.glass)
    .padding()
    .accessibilityIdentifier("channelGuideButton")
  }

  private var sidebar: some View {
    VStack(spacing: 0) {
      Button {
        withAnimation { showingGuide = false }
      } label: {
        Image(systemName: "sidebar.leading")
          .font(.title)
      }
      .buttonStyle(.glass)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding()

      ChannelListView(
        viewModel: channelListVM,
        onSelectChannel: { channel in
          selectedChannel = channel
          withAnimation { showingGuide = false }
        }
      )

      Divider()

      Button("Sign Out") {
        Task { await appState.logout() }
      }
      .accessibilityIdentifier("signOutButton")
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(width: sidebarWidth)
    .frame(maxHeight: .infinity)
    .background(.ultraThinMaterial)
  }

  private func autoSelectChannel() {
    let allChannels = channelListVM.channelGroups.flatMap(\.channels)
    if !lastChannelId.isEmpty,
       let channel = allChannels.first(where: { $0.id == lastChannelId }) {
      selectedChannel = channel
    } else if let live = allChannels.first(where: { $0.running == 1 }) {
      selectedChannel = live
    } else if let first = allChannels.first {
      selectedChannel = first
    }
  }

  private func playChannel(_ channel: ChannelDTO) {
    lastChannelId = channel.id
    guard let url = StreamURLBuilder.liveStreamURL(
      liveHost: session.productConfig.liveHost,
      playpath: channel.playpath,
      accessToken: session.accessToken
    ) else { return }

    let referer = session.productConfig.vmsReferer
    playerManager.loadLiveStream(url: url, referer: referer)
    playerManager.setNowPlayingInfo(title: channel.name, isLiveStream: true)
  }
}

// MARK: - macOS native sidebar

#if os(macOS)
/// Native NavigationSplitView layout for macOS: sidebar with channel list, detail with player
private struct MacAuthenticatedContainer: View {
  let appState: AppState
  let session: AuthService.Session
  @State private var playerManager = PlayerManager()
  @State private var channelListVM: ChannelListViewModel
  @State private var selectedChannel: ChannelDTO?
  @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
  @AppStorage("lastChannelId") private var lastChannelId: String = ""

  init(appState: AppState, session: AuthService.Session) {
    self.appState = appState
    self.session = session
    self._channelListVM = State(initialValue: ChannelListViewModel(
      channelService: appState.channelService,
      config: session.productConfig
    ))
  }

  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      sidebarContent
        .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 360)
    } detail: {
      PlayerView(playerManager: playerManager, isLive: playerManager.isLive)
        .ignoresSafeArea()
    }
    .task {
      await channelListVM.loadChannels()
      autoSelectChannel()
    }
    .onChange(of: selectedChannel) { _, channel in
      if let channel {
        playChannel(channel)
      }
    }
  }

  private var sidebarContent: some View {
    Group {
      if channelListVM.isLoading && channelListVM.channelGroups.isEmpty {
        ProgressView("Loading channels...")
      } else if let error = channelListVM.errorMessage, channelListVM.channelGroups.isEmpty {
        ContentUnavailableView {
          Label("Error", systemImage: "exclamationmark.triangle")
        } description: {
          Text(error)
        } actions: {
          Button("Retry") { Task { await channelListVM.loadChannels() } }
        }
      } else {
        List(selection: $selectedChannel) {
          ForEach(channelListVM.filteredGroups, id: \.category) { group in
            Section(group.category) {
              ForEach(group.channels) { channel in
                ChannelRow(channel: channel, channelListHost: "")
                  .tag(channel)
              }
            }
          }
        }
        .listStyle(.sidebar)
        .accessibilityIdentifier("channelList")
      }
    }
  }

  private func autoSelectChannel() {
    let allChannels = channelListVM.channelGroups.flatMap(\.channels)
    if !lastChannelId.isEmpty,
       let channel = allChannels.first(where: { $0.id == lastChannelId }) {
      selectedChannel = channel
    } else if let live = allChannels.first(where: { $0.running == 1 }) {
      selectedChannel = live
    } else if let first = allChannels.first {
      selectedChannel = first
    }
  }

  private func playChannel(_ channel: ChannelDTO) {
    lastChannelId = channel.id
    guard let url = StreamURLBuilder.liveStreamURL(
      liveHost: session.productConfig.liveHost,
      playpath: channel.playpath,
      accessToken: session.accessToken
    ) else { return }

    let referer = session.productConfig.vmsReferer
    playerManager.loadLiveStream(url: url, referer: referer)
    playerManager.setNowPlayingInfo(title: channel.name, isLiveStream: true)
  }
}
#endif
