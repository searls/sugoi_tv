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

// MARK: - Shared playback controller

@MainActor @Observable
final class ChannelPlaybackController {
  let playerManager = PlayerManager()
  let channelListVM: ChannelListViewModel
  var selectedChannel: ChannelDTO?
  @ObservationIgnored @AppStorage("lastChannelId") var lastChannelId: String = ""

  private let session: AuthService.Session

  init(appState: AppState, session: AuthService.Session) {
    self.session = session
    self.channelListVM = ChannelListViewModel(
      channelService: appState.channelService,
      config: session.productConfig
    )
  }

  func loadAndAutoSelect() async {
    await channelListVM.loadChannels()
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

  func playChannel(_ channel: ChannelDTO) {
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

// MARK: - iOS overlay sidebar layout

/// Video-first layout: player fills the window, channel guide slides in as a sidebar
private struct AuthenticatedContainer: View {
  let appState: AppState
  @State private var controller: ChannelPlaybackController
  @State private var showingGuide = false

  private let sidebarWidth: CGFloat = 340

  init(appState: AppState, session: AuthService.Session) {
    self.appState = appState
    self._controller = State(initialValue: ChannelPlaybackController(
      appState: appState, session: session
    ))
  }

  var body: some View {
    ZStack(alignment: .topLeading) {
      PlayerView(playerManager: controller.playerManager)
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
    .task { await controller.loadAndAutoSelect() }
    .onChange(of: controller.selectedChannel) { _, channel in
      if let channel { controller.playChannel(channel) }
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
        viewModel: controller.channelListVM,
        onSelectChannel: { channel in
          controller.selectedChannel = channel
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
}

// MARK: - macOS native sidebar layout

#if os(macOS)
/// Native NavigationSplitView layout for macOS: sidebar with channel list, detail with player
private struct MacAuthenticatedContainer: View {
  let appState: AppState
  @State private var controller: ChannelPlaybackController
  @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn

  init(appState: AppState, session: AuthService.Session) {
    self.appState = appState
    self._controller = State(initialValue: ChannelPlaybackController(
      appState: appState, session: session
    ))
  }

  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      sidebarContent
        .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 360)
    } detail: {
      PlayerView(playerManager: controller.playerManager)
        .ignoresSafeArea()
    }
    .task { await controller.loadAndAutoSelect() }
    .onChange(of: controller.selectedChannel) { _, channel in
      if let channel { controller.playChannel(channel) }
    }
  }

  private var sidebarContent: some View {
    Group {
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
        List(selection: $controller.selectedChannel) {
          ForEach(controller.channelListVM.filteredGroups, id: \.category) { group in
            Section(group.category) {
              ForEach(group.channels) { channel in
                ChannelRow(channel: channel)
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
}
#endif
