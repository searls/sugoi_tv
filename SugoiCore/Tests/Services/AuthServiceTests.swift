import Foundation
import Testing

@testable import SugoiCore

@Suite("AuthService")
struct AuthServiceTests {
  static let loginJSON = """
    {
      "access_token": "test_access_token+/==",
      "token_type": "bearer",
      "expires_in": 1770770216,
      "refresh_token": "test_refresh_token",
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

  @Test("Login stores session in Keychain and returns Session")
  func loginSuccess() async throws {
    let mock = MockHTTPSession()
    mock.requestHandler = { request in
      #expect(request.url!.absoluteString.contains("logon.sjs"))
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(Self.loginJSON.utf8))
    }

    let keychain = MockKeychainService()
    let client = APIClient(session: mock.session)
    let auth = AuthService(keychain: keychain, apiClient: client)

    let session = try await auth.login(cid: "testuser", password: "testpass")

    #expect(session.accessToken == "test_access_token+/==")
    #expect(session.cid == "AABC538835997")
    #expect(session.productConfig.vmsHost == "http://live.yoitv.com:9083")

    // Verify Keychain was updated
    #expect(try await keychain.accessToken() == "test_access_token+/==")
    #expect(try await keychain.refreshToken() == "test_refresh_token")
    #expect(try await keychain.cid() == "AABC538835997")
  }

  @Test("Login with non-OK code throws loginFailed")
  func loginFailure() async {
    let mock = MockHTTPSession()
    let failJSON = #"{"access_token":"","token_type":"","expires_in":0,"refresh_token":"","expired":false,"disabled":false,"confirmed":true,"cid":"","type":"","trial":0,"create_time":0,"expire_time":0,"product_config":"{}","server_time":0,"code":"INVALID"}"#
    mock.requestHandler = { request in
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(failJSON.utf8))
    }

    let auth = AuthService(keychain: MockKeychainService(), apiClient: APIClient(session: mock.session))
    do {
      _ = try await auth.login(cid: "bad", password: "bad")
      #expect(Bool(false), "Should have thrown")
    } catch let error as AuthError {
      #expect(error == .loginFailed(code: "INVALID"))
    } catch {
      #expect(Bool(false), "Wrong error: \(error)")
    }
  }

  @Test("Refresh with AUTH code clears session")
  func refreshAuthFailure() async throws {
    let mock = MockHTTPSession()
    let counter = CallCounter()
    mock.requestHandler = { request in
      let count = counter.increment()
      let json: String
      if count == 1 {
        json = Self.loginJSON
      } else {
        json = #"{"access_token":"","token_type":"","expires_in":0,"refresh_token":"","expired":false,"disabled":false,"confirmed":true,"cid":"","type":"","trial":0,"create_time":0,"expire_time":0,"product_config":"{}","server_time":0,"code":"AUTH"}"#
      }
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(json.utf8))
    }

    let keychain = MockKeychainService()
    let client = APIClient(session: mock.session)
    let auth = AuthService(keychain: keychain, apiClient: client)

    _ = try await auth.login(cid: "user", password: "pass")

    do {
      _ = try await auth.refreshTokens()
      #expect(Bool(false), "Should have thrown")
    } catch let error as AuthError {
      #expect(error == .sessionExpired)
    }

    // Session should be cleared
    let session = await auth.session
    #expect(session == nil)
    #expect(try await keychain.accessToken() == nil)
  }

  // MARK: - Restore session

  @Test("Restore returns stored session from keychain without network call")
  func restoreFromKeychain() async throws {
    let keychain = MockKeychainService()
    try await keychain.storeSession(
      accessToken: "stored_token", refreshToken: "stored_refresh",
      cid: "AABC538835997",
      productConfigJSON: #"{"vms_host":"http://live.yoitv.com:9083","vms_vod_host":"http://vod.yoitv.com:9083","vms_uid":"UID1","vms_live_cid":"CID1","vms_referer":"http://play.yoitv.com","epg_days":30,"single":"https://crm.yoitv.com/single.sjs"}"#
    )

    let mock = MockHTTPSession()
    mock.requestHandler = { _ in
      Issue.record("restoreSession should not make network requests")
      throw URLError(.badURL)
    }

    let auth = AuthService(keychain: keychain, apiClient: APIClient(session: mock.session))
    let session = try await auth.restoreSession()

    #expect(session != nil)
    #expect(session?.accessToken == "stored_token")
    #expect(session?.cid == "AABC538835997")
    // Keychain should be untouched
    #expect(try await keychain.accessToken() == "stored_token")
  }

  @Test("Restore returns nil when keychain is empty")
  func restoreEmptyKeychain() async throws {
    let mock = MockHTTPSession()
    let auth = AuthService(keychain: MockKeychainService(), apiClient: APIClient(session: mock.session))
    let session = try await auth.restoreSession()
    #expect(session == nil)
  }

  // MARK: - Logout

  @Test("Logout clears session and Keychain")
  func logout() async throws {
    let mock = MockHTTPSession()
    mock.requestHandler = { request in
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(Self.loginJSON.utf8))
    }

    let keychain = MockKeychainService()
    let auth = AuthService(keychain: keychain, apiClient: APIClient(session: mock.session))

    _ = try await auth.login(cid: "user", password: "pass")
    await auth.logout()

    let session = await auth.session
    #expect(session == nil)
    #expect(try await keychain.accessToken() == nil)
  }
}
