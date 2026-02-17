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
    let programGuide = ProgramGuideService(apiClient: client)
    let appState = AppState(apiClient: client, authService: auth, channelService: channels, programGuideService: programGuide)

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

  @Test("Re-selects when previously selected channel disappears from fresh list")
  func reSelectsWhenChannelDisappears() async throws {
    let controller = try makeController(channelsJSON: Self.channelsJSON)
    // Pre-set a channel that won't exist in the fresh response
    controller.selectedChannel = ChannelDTO(
      id: "REMOVED", uid: nil, name: "Gone Channel", description: nil, tags: nil,
      no: 99, timeshift: nil, timeshiftLen: nil, epgKeepDays: nil, state: nil,
      running: nil, playpath: "/gone", liveType: nil
    )
    controller.lastChannelId = ""

    await controller.loadAndAutoSelect()

    // Should have re-selected to a channel from the fresh list (CH1 = running)
    #expect(controller.selectedChannel?.id != "REMOVED")
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
    let programGuide = ProgramGuideService(apiClient: client)
    let appState = AppState(apiClient: client, authService: auth, channelService: channels, programGuideService: programGuide)

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
    let programGuide = ProgramGuideService(apiClient: client)
    let appState = AppState(apiClient: client, authService: auth, channelService: channels, programGuideService: programGuide)

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

  @Test("selectFromCache selects channel without awaiting network")
  func selectFromCacheImmediate() throws {
    let defaults = seededDefaults()
    let controller = try makeController(channelsJSON: Self.channelsJSON, defaults: defaults)
    controller.lastChannelId = "CH2"

    // selectFromCache is synchronous — no await needed
    controller.selectFromCache()

    #expect(controller.selectedChannel?.id == "CH2")
  }

  @Test("selectFromCache is no-op with empty cache")
  func selectFromCacheEmpty() throws {
    let emptyDefaults = UserDefaults(suiteName: "test.cache.empty2.\(UUID().uuidString)")!
    let controller = try makeController(channelsJSON: Self.channelsJSON, defaults: emptyDefaults)

    controller.selectFromCache()

    #expect(controller.selectedChannel == nil)
  }

  @Test("refreshChannelList fetches and updates selection when cache was empty")
  func refreshAfterEmptyCache() async throws {
    let emptyDefaults = UserDefaults(suiteName: "test.cache.empty3.\(UUID().uuidString)")!
    let controller = try makeController(channelsJSON: Self.channelsJSON, defaults: emptyDefaults)
    controller.lastChannelId = "CH3"

    // No selection from empty cache
    controller.selectFromCache()
    #expect(controller.selectedChannel == nil)

    // Network fetch provides channels, re-selects
    await controller.refreshChannelList()
    #expect(controller.selectedChannel?.id == "CH3")
  }

  @Test("selectFromCache + refreshChannelList matches loadAndAutoSelect behavior")
  func splitMatchesUnified() async throws {
    let defaults1 = seededDefaults()
    let defaults2 = seededDefaults()
    let controller1 = try makeController(channelsJSON: Self.channelsJSON, defaults: defaults1)
    let controller2 = try makeController(channelsJSON: Self.channelsJSON, defaults: defaults2)
    controller1.lastChannelId = "CH2"
    controller2.lastChannelId = "CH2"

    // Unified path
    await controller1.loadAndAutoSelect()

    // Split path
    controller2.selectFromCache()
    await controller2.refreshChannelList()

    #expect(controller1.selectedChannel?.id == controller2.selectedChannel?.id)
  }

  @Test("playChannel after selectFromCache moves player out of idle — guards against double-play")
  func playChannelExitsIdle() throws {
    let defaults = seededDefaults()
    let controller = try makeController(channelsJSON: Self.channelsJSON, defaults: defaults)
    controller.lastChannelId = "CH1"

    controller.selectFromCache()
    #expect(controller.playerManager.state == .idle)

    // First play — transitions out of idle
    controller.playChannel(controller.selectedChannel!)
    #expect(controller.playerManager.state != .idle)

    // A second playChannel would restart the stream; the view guards
    // against this by checking playerManager.state == .idle
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
    let programGuide = ProgramGuideService(apiClient: client)
    let appState = AppState(apiClient: client, authService: auth, channelService: channels, programGuideService: programGuide)

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
    let programGuide = ProgramGuideService(apiClient: client)
    let appState = AppState(apiClient: client, authService: auth, channelService: channels, programGuideService: programGuide)

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
    #expect(controller.preferredCompactColumn == .sidebar)

    await controller.loadAndAutoSelect()
    // autoSelectChannel no longer auto-plays; explicitly play
    controller.playChannel(controller.selectedChannel!)

    #expect(controller.preferredCompactColumn == .detail)
  }
}

@Suite("ChannelPlaybackController.playVOD")
@MainActor
struct ChannelPlaybackControllerPlayVODTests {
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
    let programGuide = ProgramGuideService(apiClient: client)
    let appState = AppState(apiClient: client, authService: auth, channelService: channels, programGuideService: programGuide)

    let loginResponse = try JSONDecoder().decode(LoginResponse.self, from: Data(Self.testLoginJSON.utf8))
    let config = try loginResponse.parseProductConfig()
    let session = AuthService.Session(from: loginResponse, config: config)

    let defaults = UserDefaults(suiteName: "test.vod.\(UUID().uuidString)")!
    return ChannelPlaybackController(appState: appState, session: session, defaults: defaults)
  }

  @Test("playVOD loads VOD stream and switches to detail column")
  func playVODLoadsStream() throws {
    let controller = try makeController()
    let program = ProgramDTO(time: 1000, title: "Past Show", path: "/query/past_show")

    controller.playVOD(program: program, channelName: "NHK")

    #expect(controller.preferredCompactColumn == .detail)
    #expect(controller.playerManager.state != .idle)
  }

  @Test("playVOD does nothing when program has no VOD")
  func playVODNoOpWithoutVOD() throws {
    let controller = try makeController()
    let program = ProgramDTO(time: 1000, title: "Live Only", path: "")

    controller.playVOD(program: program, channelName: "NHK")

    #expect(controller.preferredCompactColumn == .sidebar)
    #expect(controller.playerManager.state == .idle)
  }

  @Test("playVOD resets reauth flag")
  func playVODResetsReauth() throws {
    let controller = try makeController()
    controller.hasAttemptedReauth = true
    let program = ProgramDTO(time: 1000, title: "Past Show", path: "/query/past_show")

    controller.playVOD(program: program, channelName: "NHK")

    #expect(controller.hasAttemptedReauth == false)
  }

  @Test("playVOD persists VOD program info")
  func playVODPersistsInfo() throws {
    let controller = try makeController()
    let program = ProgramDTO(time: 1000, title: "Past Show", path: "/query/past_show")

    controller.playVOD(program: program, channelName: "NHK総合")

    #expect(controller.lastPlayingProgramID == "/query/past_show")
    #expect(controller.lastPlayingProgramTitle == "Past Show")
    #expect(controller.lastPlayingChannelName == "NHK総合")
  }

  @Test("playChannel clears VOD persistence")
  func playChannelClearsVODInfo() throws {
    let controller = try makeController()
    let program = ProgramDTO(time: 1000, title: "Past Show", path: "/query/past_show")
    controller.playVOD(program: program, channelName: "NHK総合")

    let channel = ChannelDTO(
      id: "CH1", uid: nil, name: "NHK総合", description: nil, tags: nil,
      no: 1, timeshift: nil, timeshiftLen: nil, epgKeepDays: nil, state: nil,
      running: 1, playpath: "/query/s/nhk", liveType: nil
    )
    controller.playChannel(channel)

    #expect(controller.lastPlayingProgramID == "")
    #expect(controller.lastPlayingProgramTitle == "")
    #expect(controller.lastPlayingChannelName == "")
    #expect(controller.lastVODPosition == 0)
  }
}

@Suite("ChannelPlaybackController.replayCurrentStream")
@MainActor
struct ChannelPlaybackControllerReplayTests {
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
    let programGuide = ProgramGuideService(apiClient: client)
    let appState = AppState(apiClient: client, authService: auth, channelService: channels, programGuideService: programGuide)

    let loginResponse = try JSONDecoder().decode(LoginResponse.self, from: Data(Self.testLoginJSON.utf8))
    let config = try loginResponse.parseProductConfig()
    let session = AuthService.Session(from: loginResponse, config: config)

    let defaults = UserDefaults(suiteName: "test.replay.\(UUID().uuidString)")!
    return ChannelPlaybackController(appState: appState, session: session, defaults: defaults)
  }

  @Test("Replays VOD when VOD was playing")
  func replaysVOD() throws {
    let controller = try makeController()
    let program = ProgramDTO(time: 1000, title: "Past Show", path: "/query/past_show")
    controller.playVOD(program: program, channelName: "NHK総合")

    #expect(controller.playingProgramID == "/query/past_show")

    controller.replayCurrentStream()

    // Must still be VOD, not switched to live
    #expect(controller.playingProgramID == "/query/past_show")
    #expect(controller.lastPlayingProgramID == "/query/past_show")
    #expect(controller.lastPlayingProgramTitle == "Past Show")
    #expect(controller.lastPlayingChannelName == "NHK総合")
  }

  @Test("Replays live when live was playing via sidebarPath")
  func replaysLiveFromSidebarPath() throws {
    let controller = try makeController()
    let channel = ChannelDTO(
      id: "CH1", uid: nil, name: "NHK総合", description: nil, tags: nil,
      no: 1, timeshift: nil, timeshiftLen: nil, epgKeepDays: nil, state: nil,
      running: 1, playpath: "/query/s/nhk", liveType: nil
    )
    controller.sidebarPath = [channel]
    controller.playChannel(channel)

    #expect(controller.playingProgramID == nil)

    controller.replayCurrentStream()

    #expect(controller.playingProgramID == nil)
    #expect(controller.lastPlayingProgramID == "")
  }

  @Test("Replays live using selectedChannel when sidebarPath is empty")
  func replaysLiveFromSelectedChannel() throws {
    let controller = try makeController()
    let channel = ChannelDTO(
      id: "CH1", uid: nil, name: "NHK総合", description: nil, tags: nil,
      no: 1, timeshift: nil, timeshiftLen: nil, epgKeepDays: nil, state: nil,
      running: 1, playpath: "/query/s/nhk", liveType: nil
    )
    controller.selectedChannel = channel
    controller.playChannel(channel)

    // sidebarPath is empty — playing live from channel list
    #expect(controller.sidebarPath.isEmpty)
    #expect(controller.playingProgramID == nil)

    controller.replayCurrentStream()

    // Should still replay via selectedChannel fallback
    #expect(controller.playerManager.state != .idle)
    #expect(controller.playingProgramID == nil)
  }

  @Test("Preserves persisted VOD position on replay")
  func preservesVODPosition() throws {
    let controller = try makeController()
    let program = ProgramDTO(time: 1000, title: "Past Show", path: "/query/past_show")
    controller.playVOD(program: program, channelName: "NHK総合")
    controller.lastVODPosition = 300

    controller.replayCurrentStream()

    // VOD persistence intact — position not wiped
    #expect(controller.lastPlayingProgramID == "/query/past_show")
    #expect(controller.lastVODPosition != 0)
  }

  @Test("No-op when nothing is playing and no channel available")
  func noOpWhenNothingAvailable() throws {
    let controller = try makeController()

    #expect(controller.playingProgramID == nil)
    #expect(controller.sidebarPath.isEmpty)
    #expect(controller.selectedChannel == nil)

    controller.replayCurrentStream()

    #expect(controller.playerManager.state == .idle)
  }
}

@Suite("ChannelPlaybackController.sidebarPath")
@MainActor
struct ChannelPlaybackControllerSidebarPathTests {
  nonisolated static var testLoginJSON: String {
    ChannelPlaybackControllerAutoSelectTests.testLoginJSON
  }

  nonisolated static var channelsJSON: String {
    ChannelPlaybackControllerAutoSelectTests.channelsJSON
  }

  private func makeController(channelsJSON: String? = nil) throws -> ChannelPlaybackController {
    let json = channelsJSON ?? Self.channelsJSON
    let mock = MockHTTPSession()
    mock.requestHandler = { _ in
      let response = HTTPURLResponse(
        url: URL(string: "http://test.com")!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(json.utf8))
    }
    let client = APIClient(session: mock.session)
    let auth = AuthService(keychain: MockKeychainService(), apiClient: client)
    let channels = ChannelService(apiClient: client)
    let programGuide = ProgramGuideService(apiClient: client)
    let appState = AppState(apiClient: client, authService: auth, channelService: channels, programGuideService: programGuide)

    let loginResponse = try JSONDecoder().decode(LoginResponse.self, from: Data(Self.testLoginJSON.utf8))
    let config = try loginResponse.parseProductConfig()
    let session = AuthService.Session(from: loginResponse, config: config)

    let defaults = UserDefaults(suiteName: "test.sidebar.\(UUID().uuidString)")!
    return ChannelPlaybackController(appState: appState, session: session, defaults: defaults)
  }

  @Test("sidebarPath starts empty")
  func startsEmpty() throws {
    let controller = try makeController()
    #expect(controller.sidebarPath.isEmpty)
  }

  @Test("loadAndAutoSelect selects channel without drilling into program list")
  func autoSelectStaysOnChannelList() async throws {
    let controller = try makeController()
    await controller.loadAndAutoSelect()

    #expect(controller.selectedChannel != nil)
    #expect(controller.sidebarPath.isEmpty)
  }

  @Test("programListViewModel creates and caches viewmodel for channel")
  func programListVM() async throws {
    let controller = try makeController()
    await controller.loadAndAutoSelect()

    guard let channel = controller.selectedChannel else {
      Issue.record("No channel selected")
      return
    }

    let vm1 = controller.programListViewModel(for: channel)
    #expect(vm1.channelID == channel.id)
    #expect(vm1.channelName == channel.name)

    // Same channel returns same cached instance
    let vm2 = controller.programListViewModel(for: channel)
    #expect(vm1 === vm2)
  }
}

// MARK: - Permission error detection

@Suite("String.looksLikePermissionError")
struct LooksLikePermissionErrorTests {
  @Test("Detects 'permission' keyword")
  func detectsPermission() {
    #expect("Access permission denied".looksLikePermissionError)
  }

  @Test("Detects 'authorized' keyword")
  func detectsAuthorized() {
    #expect("Not authorized to access resource".looksLikePermissionError)
  }

  @Test("Detects 'forbidden' keyword")
  func detectsForbidden() {
    #expect("403 Forbidden".looksLikePermissionError)
  }

  @Test("Detects '403' status code")
  func detects403() {
    #expect("HTTP error 403".looksLikePermissionError)
  }

  @Test("Case insensitive matching")
  func caseInsensitive() {
    #expect("PERMISSION DENIED".looksLikePermissionError)
    #expect("Forbidden".looksLikePermissionError)
  }

  @Test("Non-permission errors return false")
  func nonPermissionErrors() {
    #expect(!"Network timeout".looksLikePermissionError)
    #expect(!"File not found".looksLikePermissionError)
    #expect(!"500 Internal Server Error".looksLikePermissionError)
  }
}

// MARK: - Proxy URL fallback

@Suite("ChannelPlaybackController.playChannel proxy fallback")
@MainActor
struct PlayChannelProxyFallbackTests {
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
    let programGuide = ProgramGuideService(apiClient: client)
    let appState = AppState(apiClient: client, authService: auth, channelService: channels, programGuideService: programGuide)

    let loginResponse = try JSONDecoder().decode(LoginResponse.self, from: Data(Self.testLoginJSON.utf8))
    let config = try loginResponse.parseProductConfig()
    let session = AuthService.Session(from: loginResponse, config: config)

    let defaults = UserDefaults(suiteName: "test.proxy.\(UUID().uuidString)")!
    return ChannelPlaybackController(appState: appState, session: session, defaults: defaults)
  }

  @Test("playChannel uses direct URL when proxy is not ready")
  func playChannelDirectFallback() throws {
    let controller = try makeController()
    let channel = ChannelDTO(
      id: "CH1", uid: nil, name: "NHK総合", description: nil, tags: nil,
      no: 1, timeshift: nil, timeshiftLen: nil, epgKeepDays: nil, state: nil,
      running: 1, playpath: "/query/s/nhk", liveType: nil
    )

    // Proxy not started → falls back to direct URL
    #expect(controller.refererProxy.isReady == false)
    controller.playChannel(channel)
    #expect(controller.playerManager.state != .idle)
  }

  @Test("playVOD uses direct URL when proxy is not ready")
  func playVODDirectFallback() throws {
    let controller = try makeController()
    let program = ProgramDTO(time: 1000, title: "Past Show", path: "/query/past_show")

    #expect(controller.refererProxy.isReady == false)
    controller.playVOD(program: program, channelName: "NHK")
    #expect(controller.playerManager.state != .idle)
  }
}

// MARK: - LaunchPlayback.decide

@Suite("LaunchPlayback.decide")
struct LaunchPlaybackTests {
  let now: TimeInterval = 1_700_000_000 // arbitrary fixed time
  let recentTimestamp: TimeInterval = 1_700_000_000 - 3600 // 1 hour ago
  let staleTimestamp: TimeInterval = 1_700_000_000 - 13 * 3600 // 13 hours ago
  let exactThreshold: TimeInterval = 1_700_000_000 - 12 * 3600 // exactly 12 hours ago

  @Test("iPhone always returns doNothing")
  func iPhoneDoesNothing() {
    let result = LaunchPlayback.decide(
      isCompact: true,
      lastActiveTimestamp: recentTimestamp,
      now: now,
      lastProgramID: "/vod/show",
      lastProgramTitle: "Show",
      lastChannelName: "NHK",
      lastVODPosition: 120
    )
    #expect(result == .doNothing)
  }

  @Test("First launch returns playLive")
  func firstLaunchPlaysLive() {
    let result = LaunchPlayback.decide(
      isCompact: false,
      lastActiveTimestamp: 0,
      now: now,
      lastProgramID: "",
      lastProgramTitle: "",
      lastChannelName: "",
      lastVODPosition: 0
    )
    #expect(result == .playLive)
  }

  @Test("Stale session returns playLive")
  func staleSessionPlaysLive() {
    let result = LaunchPlayback.decide(
      isCompact: false,
      lastActiveTimestamp: staleTimestamp,
      now: now,
      lastProgramID: "/vod/show",
      lastProgramTitle: "Show",
      lastChannelName: "NHK",
      lastVODPosition: 120
    )
    #expect(result == .playLive)
  }

  @Test("Exactly at 12h threshold returns playLive")
  func exactThresholdPlaysLive() {
    let result = LaunchPlayback.decide(
      isCompact: false,
      lastActiveTimestamp: exactThreshold,
      now: now,
      lastProgramID: "/vod/show",
      lastProgramTitle: "Show",
      lastChannelName: "NHK",
      lastVODPosition: 120
    )
    #expect(result == .playLive)
  }

  @Test("Recent session with VOD returns resumeVOD")
  func recentWithVODResumes() {
    let result = LaunchPlayback.decide(
      isCompact: false,
      lastActiveTimestamp: recentTimestamp,
      now: now,
      lastProgramID: "/vod/show",
      lastProgramTitle: "Past Show",
      lastChannelName: "NHK総合",
      lastVODPosition: 300
    )
    #expect(result == .resumeVOD(
      programID: "/vod/show",
      title: "Past Show",
      channelName: "NHK総合",
      position: 300
    ))
  }

  @Test("Recent session without VOD returns playLive")
  func recentWithoutVODPlaysLive() {
    let result = LaunchPlayback.decide(
      isCompact: false,
      lastActiveTimestamp: recentTimestamp,
      now: now,
      lastProgramID: "",
      lastProgramTitle: "",
      lastChannelName: "",
      lastVODPosition: 0
    )
    #expect(result == .playLive)
  }
}
