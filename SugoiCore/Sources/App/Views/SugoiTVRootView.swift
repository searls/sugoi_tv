import SwiftUI
import os.log

private let log = Logger(subsystem: "co.searls.SugoiTV", category: "Playback")

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

// MARK: - Permission error detection

private extension String {
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

  var session: AuthService.Session
  /// One-shot guard: allows a single reauth attempt per stream load.
  /// Reset to false in playChannel(), set to true after attempting reauth.
  var hasAttemptedReauth = false

  /// Local HTTP proxy that injects Referer headers for AirPlay compatibility.
  /// When ready, stream URLs route through this proxy so the Apple TV can
  /// reach the VMS server without needing custom HTTP headers.
  let refererProxy: RefererProxy

  init(appState: AppState, session: AuthService.Session) {
    self.session = session
    self.channelListVM = ChannelListViewModel(
      channelService: appState.channelService,
      config: session.productConfig
    )
    self.refererProxy = RefererProxy(referer: session.productConfig.vmsReferer)
    refererProxy.start()
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

  /// Whether tapping the player detail area should collapse the sidebar.
  /// Returns false during AirPlay to avoid layout changes that interrupt external playback.
  var shouldCollapseSidebarOnTap: Bool {
    !playerManager.isExternalPlaybackActive
  }

  func playChannel(_ channel: ChannelDTO) {
    hasAttemptedReauth = false
    lastChannelId = channel.id
    guard let url = StreamURLBuilder.liveStreamURL(
      liveHost: session.productConfig.liveHost,
      playpath: channel.playpath,
      accessToken: session.accessToken
    ) else { return }

    // When the proxy is ready, route through it so AirPlay receivers can
    // reach the VMS server. Fall back to direct URL + AVURLAsset header
    // injection (works locally but not over AirPlay).
    if let proxiedURL = refererProxy.proxiedURL(for: url) {
      log.info("Playing via proxy: \(proxiedURL.absoluteString)")
      playerManager.loadLiveStream(url: proxiedURL, referer: "")
    } else {
      log.warning("Proxy not ready, falling back to direct URL")
      let referer = session.productConfig.vmsReferer
      playerManager.loadLiveStream(url: url, referer: referer)
    }
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
    .onChange(of: controller.playerManager.state) { _, newState in
      if case .failed(let message) = newState,
         message.looksLikePermissionError,
         !controller.hasAttemptedReauth {
        controller.hasAttemptedReauth = true
        controller.playerManager.clearError()
        Task {
          if let newSession = await appState.reauthenticate() {
            controller.session = newSession
            if let channel = controller.selectedChannel {
              controller.playChannel(channel)
            }
          }
        }
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
  @Environment(\.openSettings) private var openSettings

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
        .onTapGesture {
          guard controller.shouldCollapseSidebarOnTap else { return }
          if columnVisibility != .detailOnly {
            withAnimation {
              columnVisibility = .detailOnly
            }
          }
        }
    }
    .task { await controller.loadAndAutoSelect() }
    .onChange(of: controller.selectedChannel) { _, channel in
      if let channel { controller.playChannel(channel) }
    }
    .onChange(of: controller.playerManager.state) { _, newState in
      if case .failed(let message) = newState,
         message.looksLikePermissionError,
         !controller.hasAttemptedReauth {
        controller.hasAttemptedReauth = true
        controller.playerManager.clearError()
        Task {
          if let newSession = await appState.reauthenticate() {
            controller.session = newSession
            if let channel = controller.selectedChannel {
              controller.playChannel(channel)
            }
          } else {
            openSettings()
          }
        }
      }
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
                ChannelRow(
                  channel: channel,
                  thumbnailURL: StreamURLBuilder.thumbnailURL(
                    channelListHost: controller.channelListVM.config.channelListHost,
                    playpath: channel.playpath
                  )
                )
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
