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

// MARK: - Container Previews

#if DEBUG

/// Returns canned channel data for any API request, enabling previews without network access.
private actor PreviewChannelAPIClient: APIClientProtocol {
  func get<T: Decodable & Sendable>(url: URL, headers: [String: String]) async throws -> T {
    try JSONDecoder().decode(T.self, from: Data(Self.channelJSON.utf8))
  }

  func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(
    url: URL, headers: [String: String], body: Body
  ) async throws -> Response {
    fatalError("Unused in preview")
  }

  private static let channelJSON = """
  {"code":"OK","result":[
    {"id":"CH1","name":"NHK総合","description":"NHK General","tags":"$LIVE_CAT_関東","no":1,"playpath":"/query/s/nhk","running":1},
    {"id":"CH2","name":"NHK Eテレ","description":"NHK Educational","tags":"$LIVE_CAT_関東","no":2,"playpath":"/query/s/nhke","running":1},
    {"id":"CH3","name":"日本テレビ","description":"Nippon TV","tags":"$LIVE_CAT_関東","no":3,"playpath":"/query/s/ntv","running":0},
    {"id":"CH4","name":"テレビ朝日","description":"TV Asahi","tags":"$LIVE_CAT_関東","no":4,"playpath":"/query/s/tvasahi","running":0},
    {"id":"CH5","name":"TBSテレビ","description":"TBS Television","tags":"$LIVE_CAT_関東","no":5,"playpath":"/query/s/tbs","running":1},
    {"id":"CH6","name":"フジテレビ","description":"Fuji TV","tags":"$LIVE_CAT_関東","no":6,"playpath":"/query/s/fuji","running":1},
    {"id":"CH7","name":"MBS毎日放送","description":"MBS","tags":"$LIVE_CAT_関西","no":7,"playpath":"/query/s/mbs","running":1},
    {"id":"CH8","name":"ABCテレビ","description":"ABC Television","tags":"$LIVE_CAT_関西","no":8,"playpath":"/query/s/abc","running":0},
    {"id":"CH9","name":"BS日テレ","description":"BS NTV","tags":"$LIVE_CAT_BS","no":9,"playpath":"/query/s/bsntv","running":1},
    {"id":"CH10","name":"BS朝日","description":"BS Asahi","tags":"$LIVE_CAT_BS","no":10,"playpath":"/query/s/bsasahi","running":0}
  ]}
  """
}

private let previewProductConfig: ProductConfig = {
  try! JSONDecoder().decode(ProductConfig.self, from: Data("""
  {"vms_host":"http://preview.local:9083","vms_uid":"uid","vms_live_cid":"cid","vms_referer":"http://play.yoitv.com"}
  """.utf8))
}()

private let previewSession = AuthService.Session(
  accessToken: "tok", refreshToken: "ref", cid: "cid", config: previewProductConfig
)

private struct ContainerPreview: View {
  @State private var appState: AppState

  init() {
    let mock: any APIClientProtocol = PreviewChannelAPIClient()
    let keychain = KeychainService()
    _appState = State(initialValue: AppState(
      keychain: keychain,
      apiClient: APIClient(),
      authService: AuthService(keychain: keychain, apiClient: mock),
      channelService: ChannelService(apiClient: mock),
      programGuideService: ProgramGuideService(apiClient: mock)
    ))
  }

  var body: some View {
    AuthenticatedContainer(appState: appState, session: previewSession)
  }
}

#Preview("Mac") {
  ContainerPreview()
    .frame(width: 900, height: 600)
}

#Preview("iPhone") {
  ContainerPreview()
    .frame(width: 393, height: 852)
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

  /// On compact layouts (iPhone), which column the NavigationSplitView should show.
  /// Starts at `.sidebar` so the channel list appears first; switches to `.detail` on play.
  var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

  /// Whether the player is being shown (pushed onto the NavigationStack in the detail pane).
  var showingPlayer = false

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
  private func autoSelectChannel() {
    let allChannels = channelListVM.channelGroups.flatMap(\.channels)
    guard !allChannels.isEmpty else { return }
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

  /// Create a ProgramListViewModel for the currently selected channel.
  func makeProgramListViewModel(for channel: ChannelDTO) -> ProgramListViewModel {
    ProgramListViewModel(
      programGuideService: programGuideService,
      config: session.productConfig,
      channelID: channel.id,
      channelName: channel.name
    )
  }

  func playChannel(_ channel: ChannelDTO) {
    hasAttemptedReauth = false
    lastChannelId = channel.id
    preferredCompactColumn = .detail
    showingPlayer = true
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

  func playVOD(program: ProgramDTO, channelName: String) {
    hasAttemptedReauth = false
    preferredCompactColumn = .detail
    showingPlayer = true
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

/// NavigationSplitView layout for all platforms: sidebar with channel list, detail with program list + player.
/// On Mac and iPad, shows sidebar + detail side-by-side. On iPhone, collapses to push/pop stack.
private struct AuthenticatedContainer: View {
  let appState: AppState
  @State private var controller: ChannelPlaybackController
  @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
  @AppStorage("sidebarVisible") private var sidebarVisible = true
  @AppStorage("lastActiveTimestamp") private var lastActiveTimestamp: Double = 0
  @Environment(\.scenePhase) private var scenePhase
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
        .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 360)
    } detail: {
      detailContent
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
            if let channel = controller.selectedChannel {
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

  @ViewBuilder
  private var detailContent: some View {
    NavigationStack {
      if let channel = controller.selectedChannel {
        ProgramListView(
          viewModel: controller.makeProgramListViewModel(for: channel),
          onPlayLive: {
            controller.playChannel(channel)
          },
          onPlayVOD: { program in
            controller.playVOD(program: program, channelName: channel.name)
          }
        )
        .id(channel.id)
        .navigationDestination(isPresented: $controller.showingPlayer) {
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
      } else {
        ContentUnavailableView("Select a Channel", systemImage: "tv")
      }
    }
  }

  private var sidebarContent: some View {
    VStack(spacing: 0) {
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

