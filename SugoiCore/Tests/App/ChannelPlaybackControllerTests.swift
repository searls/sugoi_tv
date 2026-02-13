import Foundation
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

  private func makeController(channelsJSON: String) throws -> ChannelPlaybackController {
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

    return ChannelPlaybackController(appState: appState, session: session)
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
