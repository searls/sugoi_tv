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
    let programGuide = ProgramGuideService(apiClient: client)
    return AppState(
      apiClient: client,
      authService: auth,
      channelService: channels,
      programGuideService: programGuide
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

  @Test("isRestoringSession is already false when refresh network call fires")
  func restoringFalseBeforeRefresh() async throws {
    let keychain = try await populatedKeychain()
    let stateCapture = StateCapture()
    let mock = MockHTTPSession()

    let appState = makeAppState(keychain: keychain, mock: mock)

    mock.requestHandler = { request in
      // The handler fires on a URLProtocol background thread while
      // restoreSession() is suspended at the await. The main thread is free,
      // so we can synchronously read @MainActor state.
      DispatchQueue.main.sync {
        MainActor.assumeIsolated {
          stateCapture.set(appState.isRestoringSession)
        }
      }
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(Self.refreshedLoginJSON.utf8))
    }

    await appState.restoreSession()

    // At the moment the refresh request fired, isRestoringSession was already false
    #expect(stateCapture.value == false, "isRestoringSession should be false before refresh network call")
    #expect(appState.session?.accessToken == "refreshed_token")
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

@Suite("AppState.reauthenticate")
@MainActor
struct AppStateReauthenticateTests {
  nonisolated static let loginJSON = """
    {
      "access_token": "fresh_token",
      "token_type": "bearer",
      "expires_in": 1770770216,
      "refresh_token": "fresh_refresh",
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

  private func makeAppState(
    keychain: MockKeychainService = MockKeychainService(),
    mock: MockHTTPSession
  ) -> AppState {
    let client = APIClient(session: mock.session)
    let auth = AuthService(keychain: keychain, apiClient: client)
    let channels = ChannelService(apiClient: client)
    let programGuide = ProgramGuideService(apiClient: client)
    return AppState(
      apiClient: client,
      authService: auth,
      channelService: channels,
      programGuideService: programGuide
    )
  }

  @Test("Reauthenticate success returns new session and updates appState")
  func reauthenticateSuccess() async throws {
    let keychain = MockKeychainService()
    try await keychain.storeSession(
      accessToken: "old_token", refreshToken: "old_refresh",
      cid: "AABC538835997",
      productConfigJSON: #"{"vms_host":"http://live.yoitv.com:9083","vms_vod_host":"http://vod.yoitv.com:9083","vms_uid":"UID1","vms_live_cid":"CID1","vms_referer":"http://play.yoitv.com","epg_days":30,"single":"https://crm.yoitv.com/single.sjs"}"#
    )
    try await keychain.storePassword("testpass")

    let mock = MockHTTPSession()
    mock.requestHandler = { request in
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(Self.loginJSON.utf8))
    }

    let appState = makeAppState(keychain: keychain, mock: mock)
    // Give it a stale session so we're in "authenticated" state
    appState.session = AuthService.Session(
      accessToken: "old_token", refreshToken: "old_refresh",
      cid: "AABC538835997",
      config: try JSONDecoder().decode(
        ProductConfig.self,
        from: Data(#"{"vms_host":"http://live.yoitv.com:9083","vms_vod_host":"http://vod.yoitv.com:9083","vms_uid":"UID1","vms_live_cid":"CID1","vms_referer":"http://play.yoitv.com","epg_days":30,"single":"https://crm.yoitv.com/single.sjs"}"#.utf8)
      )
    )

    let result = await appState.reauthenticate()

    #expect(result != nil)
    #expect(result?.accessToken == "fresh_token")
    #expect(appState.session?.accessToken == "fresh_token")
  }

  @Test("Reauthenticate auth failure logs out and returns nil")
  func reauthenticateAuthFailure() async throws {
    let keychain = MockKeychainService()
    // No stored password → reauthenticateWithStoredCredentials throws AuthError.noSession

    let mock = MockHTTPSession()
    let appState = makeAppState(keychain: keychain, mock: mock)
    appState.session = AuthService.Session(
      accessToken: "old_token", refreshToken: "old_refresh",
      cid: "AABC538835997",
      config: try JSONDecoder().decode(
        ProductConfig.self,
        from: Data(#"{"vms_host":"http://live.yoitv.com:9083","vms_vod_host":"http://vod.yoitv.com:9083","vms_uid":"UID1","vms_live_cid":"CID1","vms_referer":"http://play.yoitv.com","epg_days":30,"single":"https://crm.yoitv.com/single.sjs"}"#.utf8)
      )
    )

    let result = await appState.reauthenticate()

    #expect(result == nil)
    #expect(appState.session == nil)
  }

  @Test("Reauthenticate network error preserves session and password")
  func reauthenticateNetworkError() async throws {
    let keychain = MockKeychainService()
    try await keychain.storeSession(
      accessToken: "old_token", refreshToken: "old_refresh",
      cid: "AABC538835997",
      productConfigJSON: #"{"vms_host":"http://live.yoitv.com:9083","vms_vod_host":"http://vod.yoitv.com:9083","vms_uid":"UID1","vms_live_cid":"CID1","vms_referer":"http://play.yoitv.com","epg_days":30,"single":"https://crm.yoitv.com/single.sjs"}"#
    )
    try await keychain.storePassword("testpass")

    let mock = MockHTTPSession()
    mock.requestHandler = { _ in
      throw URLError(.notConnectedToInternet)
    }

    let appState = makeAppState(keychain: keychain, mock: mock)
    let config = try JSONDecoder().decode(
      ProductConfig.self,
      from: Data(#"{"vms_host":"http://live.yoitv.com:9083","vms_vod_host":"http://vod.yoitv.com:9083","vms_uid":"UID1","vms_live_cid":"CID1","vms_referer":"http://play.yoitv.com","epg_days":30,"single":"https://crm.yoitv.com/single.sjs"}"#.utf8)
    )
    appState.session = AuthService.Session(
      accessToken: "old_token", refreshToken: "old_refresh",
      cid: "AABC538835997", config: config
    )

    let result = await appState.reauthenticate()

    // Returns nil (couldn't reauth) but does NOT logout
    #expect(result == nil)
    // Session and password preserved — not wiped
    #expect(appState.session != nil)
    #expect(appState.session?.accessToken == "old_token")
    #expect(try await keychain.password() == "testpass")
  }
}
