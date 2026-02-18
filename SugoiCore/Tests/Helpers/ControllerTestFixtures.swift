import Foundation

@testable import SugoiCore

/// Shared test fixtures for ChannelPlaybackController test suites.
/// Eliminates duplication of makeController() and JSON fixtures across 7 suites.
enum ControllerTestFixtures {
  // Two categories, one channel running, to exercise all selection paths
  static let channelsJSON = """
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
  static let allStoppedJSON = """
    {
      "result": [
        {"id": "CH1", "name": "NHK総合", "tags": "$LIVE_CAT_関東", "no": 1, "playpath": "/nhk"},
        {"id": "CH2", "name": "テレビ朝日", "tags": "$LIVE_CAT_関東", "no": 2, "playpath": "/tvasahi"}
      ],
      "code": "OK"
    }
    """

  static let testLoginJSON = """
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

  @MainActor
  static func makeController(channelsJSON: String = Self.channelsJSON) throws -> ChannelPlaybackController {
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

    let loginResponse = try JSONDecoder().decode(LoginResponse.self, from: Data(testLoginJSON.utf8))
    let config = try loginResponse.parseProductConfig()
    let session = AuthService.Session(from: loginResponse, config: config)

    return ChannelPlaybackController(appState: appState, session: session)
  }
}
