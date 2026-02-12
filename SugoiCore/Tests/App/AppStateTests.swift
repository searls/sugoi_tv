import Foundation
import Testing

@testable import SugoiCore

@Suite("AppState.restoreSession")
@MainActor
struct AppStateRestoreSessionTests {
  nonisolated static let validProductConfigJSON = #"{"vms_host":"http://live.yoitv.com:9083","vms_vod_host":"http://vod.yoitv.com:9083","vms_uid":"UID1","vms_live_cid":"CID1","vms_referer":"http://play.yoitv.com","epg_days":30,"single":"https://crm.yoitv.com/single.sjs"}"#

  nonisolated static let refreshedLoginJSON = """
    {
      "access_token": "refreshed_token",
      "token_type": "bearer",
      "expires_in": 1770770216,
      "refresh_token": "refreshed_refresh",
      "expired": false,
      "disabled": false,
      "confirmed": true,
      "cid": "AABC538835997",
      "type": "tvum_cid",
      "trial": 0,
      "create_time": 1652403783,
      "expire_time": 1782959503,
      "product_config": "{\\"vms_host\\":\\"http://live.yoitv.com:9083\\",\\"vms_vod_host\\":\\"http://vod.yoitv.com:9083\\",\\"vms_uid\\":\\"UID1\\",\\"vms_live_cid\\":\\"CID1\\",\\"vms_referer\\":\\"http://play.yoitv.com\\",\\"epg_days\\":30,\\"single\\":\\"https://crm.yoitv.com/single.sjs\\"}",
      "server_time": 1770755816,
      "code": "OK"
    }
    """

  nonisolated static let authFailJSON = #"{"access_token":"","token_type":"","expires_in":0,"refresh_token":"","expired":false,"disabled":false,"confirmed":true,"cid":"","type":"","trial":0,"create_time":0,"expire_time":0,"product_config":"{}","server_time":0,"code":"AUTH"}"#

  private func makeAppState(
    keychain: MockKeychainService = MockKeychainService(),
    mock: MockHTTPSession
  ) -> AppState {
    let client = APIClient(session: mock.session)
    let auth = AuthService(keychain: keychain, apiClient: client)
    let channels = ChannelService(apiClient: client)
    let epg = EPGService(apiClient: client)
    return AppState(
      apiClient: client,
      authService: auth,
      channelService: channels,
      epgService: epg
    )
  }

  private func populatedKeychain() async throws -> MockKeychainService {
    let keychain = MockKeychainService()
    try await keychain.storeSession(
      accessToken: "stored_token",
      refreshToken: "stored_refresh",
      cid: "AABC538835997",
      productConfigJSON: Self.validProductConfigJSON
    )
    return keychain
  }

  // MARK: - No stored session

  @Test("Empty keychain → session stays nil")
  func restoreWithEmptyKeychain() async {
    let mock = MockHTTPSession()
    mock.requestHandler = { _ in
      Issue.record("Should not make network requests when keychain is empty")
      throw URLError(.badURL)
    }

    let appState = makeAppState(mock: mock)
    await appState.restoreSession()

    #expect(appState.session == nil)
    #expect(appState.isRestoringSession == false)
  }

  // MARK: - Stored session + successful refresh

  @Test("Stored session + successful refresh → session updated with fresh tokens")
  func restoreAndRefreshSuccess() async throws {
    let keychain = try await populatedKeychain()
    let mock = MockHTTPSession()
    mock.requestHandler = { request in
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(Self.refreshedLoginJSON.utf8))
    }

    let appState = makeAppState(keychain: keychain, mock: mock)
    await appState.restoreSession()

    #expect(appState.session != nil)
    #expect(appState.session?.accessToken == "refreshed_token")
    #expect(appState.isRestoringSession == false)
  }

  // MARK: - Stored session + AUTH error (session expired)

  @Test("Stored session + AUTH error on refresh → session cleared")
  func restoreAndSessionExpired() async throws {
    let keychain = try await populatedKeychain()
    let mock = MockHTTPSession()
    mock.requestHandler = { request in
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(Self.authFailJSON.utf8))
    }

    let appState = makeAppState(keychain: keychain, mock: mock)
    await appState.restoreSession()

    #expect(appState.session == nil)
    #expect(appState.isRestoringSession == false)
  }

  // MARK: - Stored session + network error (keep stale tokens)

  @Test("Stored session + network error on refresh → keeps stale session")
  func restoreAndNetworkError() async throws {
    let keychain = try await populatedKeychain()
    let mock = MockHTTPSession()
    mock.requestHandler = { _ in
      throw URLError(.notConnectedToInternet)
    }

    let appState = makeAppState(keychain: keychain, mock: mock)
    await appState.restoreSession()

    #expect(appState.session != nil)
    #expect(appState.session?.accessToken == "stored_token")
    #expect(appState.isRestoringSession == false)
  }
}
