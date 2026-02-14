import Foundation
import SwiftUI
import Testing

@testable import SugoiCore

@Suite("ChannelPlaybackController.loadAndAutoSelect")
@MainActor
struct ChannelPlaybackControllerAutoSelectTests {
  // Two categories, one channel running, to exercise all selection paths
  nonisolated static let channelsJSON = """
    {
      "result": [
        {"id": "CH1", "name": "NHK総合", "tags": "$LIVE_CAT_関東", "no": 1, "playpath": "/nhk", "running": 1},
        {"id": "CH2", "name": "テレビ朝日", "tags": "$LIVE_CAT_関東", "no": 2, "playpath": "/tvasahi"},
        {"id": "CH3", "name": "MBS毎日放送", "tags": "$LIVE_CAT_関西", "no": 3, "playpath": "/mbs"}
      ],
      "code": "OK"
    }
    """

  // All channels stopped — no running == 1
  nonisolated static let allStoppedJSON = """
    {
      "result": [
        {"id": "CH1", "name": "NHK総合", "tags": "$LIVE_CAT_関東", "no": 1, "playpath": "/nhk"},
        {"id": "CH2", "name": "テレビ朝日", "tags": "$LIVE_CAT_関東", "no": 2, "playpath": "/tvasahi"}
      ],
      "code": "OK"
    }
    """

  nonisolated static var testConfig: ProductConfig {
    ProductConfig(
      vmsHost: "http://live.yoitv.com:9083",
      vmsVodHost: nil, vmsUid: "UID", vmsLiveCid: "CID",
      vmsReferer: "http://play.yoitv.com", epgDays: nil, single: nil,
      vmsChannelListHost: nil, vmsLiveHost: nil, vmsRecordHost: nil, vmsLiveUid: nil
    )
  }

  nonisolated static var testLoginJSON: String {
    """
    {
      "access_token": "test_token",
      "token_type": "bearer",
      "expires_in": 1770770216,
      "refresh_token": "test_refresh",
      "expired": false,
      "disabled": false,
      "confirmed": true,
      "cid": "TEST123",
      "type": "tvum_cid",
      "trial": 0,
      "create_time": 1652403783,
      "expire_time": 1782959503,
      "product_config": "{\\"vms_host\\":\\"http://live.yoitv.com:9083\\",\\"vms_uid\\":\\"UID\\",\\"vms_live_cid\\":\\"CID\\",\\"vms_referer\\":\\"http://play.yoitv.com\\"}",
      "server_time": 1770755816,
      "code": "OK"
    }
    """
  }

  private func makeController(channelsJSON: String, defaults: UserDefaults? = nil) throws -> ChannelPlaybackController {
    let mock = MockHTTPSession()
    mock.requestHandler = { _ in
      let response = HTTPURLResponse(
        url: URL(string: "http://test.com")!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(channelsJSON.utf8))
    }
    let client = APIClient(session: mock.session)
    let auth = AuthService(keychain: MockKeychainService(), apiClient: client)
    let channels = ChannelService(apiClient: client)
    let epg = EPGService(apiClient: client)
    let appState = AppState(apiClient: client, authService: auth, channelService: channels, epgService: epg)

    let loginResponse = try JSONDecoder().decode(LoginResponse.self, from: Data(Self.testLoginJSON.utf8))
    let config = try loginResponse.parseProductConfig()
    let session = AuthService.Session(from: loginResponse, config: config)

    let isolatedDefaults = defaults ?? UserDefaults(suiteName: "test.autoselect.\(UUID().uuidString)")!
    return ChannelPlaybackController(appState: appState, session: session, defaults: isolatedDefaults)
  }

  @Test("Selects last-used channel when lastChannelId matches")
  func selectsLastChannel() async throws {
    let controller = try makeController(channelsJSON: Self.channelsJSON)
    controller.lastChannelId = "CH2"

    await controller.loadAndAutoSelect()

    #expect(controller.selectedChannel?.id == "CH2")
  }

  @Test("Falls back to first running channel when lastChannelId doesn't match")
  func selectsRunningChannel() async throws {
    let controller = try makeController(channelsJSON: Self.channelsJSON)
    controller.lastChannelId = "NONEXISTENT"

    await controller.loadAndAutoSelect()

    #expect(controller.selectedChannel?.id == "CH1", "CH1 is the only channel with running == 1")
  }

  @Test("Falls back to first channel when no channels are running")
  func selectsFirstChannel() async throws {
    let controller = try makeController(channelsJSON: Self.allStoppedJSON)
    controller.lastChannelId = ""

    await controller.loadAndAutoSelect()

    #expect(controller.selectedChannel?.id == "CH1", "Should pick the first channel as last resort")
  }

  @Test("Selects first running channel when no lastChannelId is set")
  func selectsRunningWithNoHistory() async throws {
    let controller = try makeController(channelsJSON: Self.channelsJSON)
    controller.lastChannelId = ""

    await controller.loadAndAutoSelect()

    #expect(controller.selectedChannel?.id == "CH1")
  }
}

@Suite("ChannelPlaybackController.loadAndAutoSelect with cache")
@MainActor
struct ChannelPlaybackControllerCacheTests {
  nonisolated static let channelsJSON = ChannelPlaybackControllerAutoSelectTests.channelsJSON
  nonisolated static let testLoginJSON = ChannelPlaybackControllerAutoSelectTests.testLoginJSON

  /// Channels that match channelsJSON, for pre-populating UserDefaults cache.
  nonisolated static let cachedChannels: [ChannelDTO] = [
    ChannelDTO(id: "CH1", uid: nil, name: "NHK総合", description: nil, tags: "$LIVE_CAT_関東", no: 1, timeshift: nil, timeshiftLen: nil, epgKeepDays: nil, state: nil, running: 1, playpath: "/nhk", liveType: nil),
    ChannelDTO(id: "CH2", uid: nil, name: "テレビ朝日", description: nil, tags: "$LIVE_CAT_関東", no: 2, timeshift: nil, timeshiftLen: nil, epgKeepDays: nil, state: nil, running: nil, playpath: "/tvasahi", liveType: nil),
    ChannelDTO(id: "CH3", uid: nil, name: "MBS毎日放送", description: nil, tags: "$LIVE_CAT_関西", no: 3, timeshift: nil, timeshiftLen: nil, epgKeepDays: nil, state: nil, running: nil, playpath: "/mbs", liveType: nil),
  ]

  /// Creates an isolated UserDefaults suite pre-seeded with cached channels.
  private func seededDefaults() -> UserDefaults {
    let defaults = UserDefaults(suiteName: "test.cache.\(UUID().uuidString)")!
    let data = try! JSONEncoder().encode(Self.cachedChannels)
    defaults.set(data, forKey: "cachedChannels")
    return defaults
  }

  private func makeController(channelsJSON: String, defaults: UserDefaults) throws -> ChannelPlaybackController {
    let mock = MockHTTPSession()
    mock.requestHandler = { _ in
      let response = HTTPURLResponse(
        url: URL(string: "http://test.com")!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(channelsJSON.utf8))
    }
    let client = APIClient(session: mock.session)
    let auth = AuthService(keychain: MockKeychainService(), apiClient: client)
    let channels = ChannelService(apiClient: client)
    let epg = EPGService(apiClient: client)
    let appState = AppState(apiClient: client, authService: auth, channelService: channels, epgService: epg)

    let loginResponse = try JSONDecoder().decode(LoginResponse.self, from: Data(Self.testLoginJSON.utf8))
    let config = try loginResponse.parseProductConfig()
    let session = AuthService.Session(from: loginResponse, config: config)

    return ChannelPlaybackController(appState: appState, session: session, defaults: defaults)
  }

  @Test("Init loads cached channels into channelGroups")
  func initLoadsCachedChannels() throws {
    let defaults = seededDefaults()
    let controller = try makeController(channelsJSON: Self.channelsJSON, defaults: defaults)

    #expect(!controller.channelListVM.channelGroups.isEmpty)
    #expect(controller.channelListVM.channelGroups[0].category == "関東")
  }

  @Test("Auto-selects last channel from cache before network fetch")
  func autoSelectsFromCache() async throws {
    let defaults = seededDefaults()
    let controller = try makeController(channelsJSON: Self.channelsJSON, defaults: defaults)
    controller.lastChannelId = "CH2"

    await controller.loadAndAutoSelect()

    #expect(controller.selectedChannel?.id == "CH2")
  }

  @Test("Auto-selects from cache even when network fails")
  func autoSelectsFromCacheOnNetworkFailure() async throws {
    let defaults = seededDefaults()

    let mock = MockHTTPSession()
    mock.requestHandler = { _ in throw URLError(.notConnectedToInternet) }
    let client = APIClient(session: mock.session)
    let auth = AuthService(keychain: MockKeychainService(), apiClient: client)
    let channels = ChannelService(apiClient: client)
    let epg = EPGService(apiClient: client)
    let appState = AppState(apiClient: client, authService: auth, channelService: channels, epgService: epg)

    let loginResponse = try JSONDecoder().decode(LoginResponse.self, from: Data(Self.testLoginJSON.utf8))
    let config = try loginResponse.parseProductConfig()
    let session = AuthService.Session(from: loginResponse, config: config)

    let controller = ChannelPlaybackController(appState: appState, session: session, defaults: defaults)
    controller.lastChannelId = "CH1"

    await controller.loadAndAutoSelect()

    // Channel selected from cache despite network failure
    #expect(controller.selectedChannel?.id == "CH1")
    #expect(!controller.channelListVM.channelGroups.isEmpty)
  }

  @Test("Empty cache does not select a channel before network fetch")
  func emptyCacheNoSelection() throws {
    let emptyDefaults = UserDefaults(suiteName: "test.cache.empty.\(UUID().uuidString)")!
    let controller = try makeController(channelsJSON: Self.channelsJSON, defaults: emptyDefaults)
    controller.lastChannelId = "CH1"

    // Before loadAndAutoSelect, no selection from empty cache
    #expect(controller.selectedChannel == nil)
    #expect(controller.channelListVM.channelGroups.isEmpty)
  }
}

@Suite("ChannelPlaybackController.shouldCollapseSidebarOnTap")
@MainActor
struct ChannelPlaybackControllerSidebarCollapseTests {
  nonisolated static var testLoginJSON: String {
    ChannelPlaybackControllerAutoSelectTests.testLoginJSON
  }

  nonisolated static var channelsJSON: String {
    ChannelPlaybackControllerAutoSelectTests.channelsJSON
  }

  private func makeController() throws -> ChannelPlaybackController {
    let mock = MockHTTPSession()
    mock.requestHandler = { _ in
      let response = HTTPURLResponse(
        url: URL(string: "http://test.com")!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(Self.channelsJSON.utf8))
    }
    let client = APIClient(session: mock.session)
    let auth = AuthService(keychain: MockKeychainService(), apiClient: client)
    let channels = ChannelService(apiClient: client)
    let epg = EPGService(apiClient: client)
    let appState = AppState(apiClient: client, authService: auth, channelService: channels, epgService: epg)

    let loginResponse = try JSONDecoder().decode(LoginResponse.self, from: Data(Self.testLoginJSON.utf8))
    let config = try loginResponse.parseProductConfig()
    let session = AuthService.Session(from: loginResponse, config: config)

    let defaults = UserDefaults(suiteName: "test.sidebar.\(UUID().uuidString)")!
    return ChannelPlaybackController(appState: appState, session: session, defaults: defaults)
  }

  @Test("Allows sidebar collapse when external playback is inactive")
  func allowsCollapseByDefault() throws {
    let controller = try makeController()

    #expect(controller.playerManager.isExternalPlaybackActive == false)
    #expect(controller.shouldCollapseSidebarOnTap == true)
  }

  @Test("Prevents sidebar collapse when AirPlay is active")
  func preventsCollapseDuringAirPlay() throws {
    let controller = try makeController()
    // Simulate AirPlay becoming active (KVO would set this in production)
    controller.playerManager.setExternalPlaybackActiveForTesting(true)

    #expect(controller.shouldCollapseSidebarOnTap == false)
  }

  @Test("Re-allows sidebar collapse after AirPlay stops")
  func reallowsCollapseAfterAirPlayStops() throws {
    let controller = try makeController()
    controller.playerManager.setExternalPlaybackActiveForTesting(true)
    #expect(controller.shouldCollapseSidebarOnTap == false)

    controller.playerManager.setExternalPlaybackActiveForTesting(false)
    #expect(controller.shouldCollapseSidebarOnTap == true)
  }
}

@Suite("ChannelPlaybackController.preferredCompactColumn")
@MainActor
struct ChannelPlaybackControllerCompactColumnTests {
  nonisolated static var testLoginJSON: String {
    ChannelPlaybackControllerAutoSelectTests.testLoginJSON
  }

  nonisolated static var channelsJSON: String {
    ChannelPlaybackControllerAutoSelectTests.channelsJSON
  }

  private func makeController() throws -> ChannelPlaybackController {
    let mock = MockHTTPSession()
    mock.requestHandler = { _ in
      let response = HTTPURLResponse(
        url: URL(string: "http://test.com")!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(Self.channelsJSON.utf8))
    }
    let client = APIClient(session: mock.session)
    let auth = AuthService(keychain: MockKeychainService(), apiClient: client)
    let channels = ChannelService(apiClient: client)
    let epg = EPGService(apiClient: client)
    let appState = AppState(apiClient: client, authService: auth, channelService: channels, epgService: epg)

    let loginResponse = try JSONDecoder().decode(LoginResponse.self, from: Data(Self.testLoginJSON.utf8))
    let config = try loginResponse.parseProductConfig()
    let session = AuthService.Session(from: loginResponse, config: config)

    let defaults = UserDefaults(suiteName: "test.compact.\(UUID().uuidString)")!
    return ChannelPlaybackController(appState: appState, session: session, defaults: defaults)
  }

  @Test("Starts on sidebar column for compact layouts")
  func startsOnSidebar() throws {
    let controller = try makeController()
    #expect(controller.preferredCompactColumn == .sidebar)
  }

  @Test("Switches to detail column when playing a channel")
  func switchesToDetailOnPlay() async throws {
    let controller = try makeController()
    await controller.loadAndAutoSelect()

    #expect(controller.preferredCompactColumn == .sidebar)

    if let channel = controller.selectedChannel {
      controller.playChannel(channel)
    }
    #expect(controller.preferredCompactColumn == .detail)
  }
}
