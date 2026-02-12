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

/// Video-first layout: player fills the window, channel guide is a floating overlay
private struct AuthenticatedContainer: View {
  let appState: AppState
  let session: AuthService.Session
  @State private var playerManager = PlayerManager()
  @State private var channelListVM: ChannelListViewModel
  @State private var selectedChannel: ChannelDTO?
  @State private var showingGuide = false
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
    ZStack(alignment: .topLeading) {
      PlayerView(playerManager: playerManager, isLive: playerManager.isLive)
        .ignoresSafeArea()

      Button {
        showingGuide.toggle()
      } label: {
        Image(systemName: "list.bullet")
          .font(.title3)
          .padding(10)
      }
      .buttonStyle(.plain)
      .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
      .padding()
      .popover(isPresented: $showingGuide) {
        channelGuide
      }
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

  private var channelGuide: some View {
    VStack(spacing: 0) {
      ChannelListView(
        viewModel: channelListVM,
        onSelectChannel: { channel in
          selectedChannel = channel
          showingGuide = false
        }
      )

      Divider()

      Button("Sign Out") {
        Task { await appState.logout() }
      }
      .buttonStyle(.plain)
      .font(.footnote)
      .foregroundStyle(.secondary)
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(width: 320, height: 500)
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
