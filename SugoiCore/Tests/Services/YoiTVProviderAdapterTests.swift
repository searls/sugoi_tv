import Foundation
import Testing

@testable import SugoiCore

// MARK: - Shared fixtures

private let validProductConfigJSON = #"{"vms_host":"http://live.yoitv.com:9083","vms_vod_host":"http://vod.yoitv.com:9083","vms_uid":"UID1","vms_live_cid":"CID1","vms_referer":"http://play.yoitv.com","epg_days":30,"single":"https://crm.yoitv.com/single.sjs"}"#

private let refreshedLoginJSON = """
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

private let authFailJSON = #"{"access_token":"","token_type":"","expires_in":0,"refresh_token":"","expired":false,"disabled":false,"confirmed":true,"cid":"","type":"","trial":0,"create_time":0,"expire_time":0,"product_config":"{}","server_time":0,"code":"AUTH"}"#

private func makeAdapter(
  keychain: MockKeychainService = MockKeychainService(),
  mock: MockHTTPSession
) -> YoiTVProviderAdapter {
  let client = APIClient(session: mock.session)
  return YoiTVProviderAdapter(keychain: keychain, apiClient: client)
}

private func populatedKeychain() async throws -> MockKeychainService {
  let keychain = MockKeychainService()
  try await keychain.storeSession(
    accessToken: "stored_token",
    refreshToken: "stored_refresh",
    cid: "AABC538835997",
    productConfigJSON: validProductConfigJSON
  )
  return keychain
}

// MARK: - restoreSession

@Suite("YoiTVProviderAdapter.restoreSession")
struct YoiTVProviderAdapterRestoreTests {
  @Test("Empty keychain → returns false")
  func restoreWithEmptyKeychain() async {
    let mock = MockHTTPSession()
    mock.requestHandler = { _ in
      Issue.record("Should not make network requests when keychain is empty")
      throw URLError(.badURL)
    }

    let adapter = makeAdapter(mock: mock)
    let restored = try? await adapter.restoreSession()

    #expect(restored == false || restored == nil)
    #expect(adapter.isAuthenticated == false)
  }

  @Test("Stored session + successful refresh → authenticated with fresh tokens")
  func restoreAndRefreshSuccess() async throws {
    let keychain = try await populatedKeychain()
    let mock = MockHTTPSession()
    mock.requestHandler = { _ in
      let response = HTTPURLResponse(
        url: URL(string: "http://test.com")!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(refreshedLoginJSON.utf8))
    }

    let adapter = makeAdapter(keychain: keychain, mock: mock)
    let restored = try await adapter.restoreSession()

    #expect(restored == true)
    #expect(adapter.isAuthenticated == true)
    #expect(adapter.accessToken == "refreshed_token")
  }

  @Test("Stored session + AUTH error on refresh → session cleared")
  func restoreAndSessionExpired() async throws {
    let keychain = try await populatedKeychain()
    let mock = MockHTTPSession()
    mock.requestHandler = { _ in
      let response = HTTPURLResponse(
        url: URL(string: "http://test.com")!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(authFailJSON.utf8))
    }

    let adapter = makeAdapter(keychain: keychain, mock: mock)
    let restored = try await adapter.restoreSession()

    #expect(restored == false)
    #expect(adapter.isAuthenticated == false)
  }

  @Test("Stored session + network error on refresh → keeps stale session")
  func restoreAndNetworkError() async throws {
    let keychain = try await populatedKeychain()
    let mock = MockHTTPSession()
    mock.requestHandler = { _ in
      throw URLError(.notConnectedToInternet)
    }

    let adapter = makeAdapter(keychain: keychain, mock: mock)
    let restored = try await adapter.restoreSession()

    #expect(restored == true)
    #expect(adapter.isAuthenticated == true)
    #expect(adapter.accessToken == "stored_token")
  }
}

// MARK: - reauthenticate

@Suite("YoiTVProviderAdapter.reauthenticate")
struct YoiTVProviderAdapterReauthTests {
  @Test("Reauthenticate success with stored password → new tokens")
  func reauthenticateSuccess() async throws {
    let keychain = try await populatedKeychain()
    try await keychain.storePassword("testpass")

    let mock = MockHTTPSession()
    mock.requestHandler = { _ in
      let response = HTTPURLResponse(
        url: URL(string: "http://test.com")!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(refreshedLoginJSON.utf8))
    }

    let adapter = makeAdapter(keychain: keychain, mock: mock)
    // Establish initial session first
    _ = try await adapter.restoreSession()

    let success = try await adapter.reauthenticate()

    #expect(success == true)
    #expect(adapter.isAuthenticated == true)
  }

  @Test("Reauthenticate with no stored password → logs out and returns false")
  func reauthenticateNoPassword() async throws {
    let keychain = try await populatedKeychain()
    // No stored password

    let mock = MockHTTPSession()
    mock.requestHandler = { _ in
      throw URLError(.notConnectedToInternet)
    }

    let adapter = makeAdapter(keychain: keychain, mock: mock)

    let success = try await adapter.reauthenticate()

    #expect(success == false)
    #expect(adapter.isAuthenticated == false)
  }
}

// MARK: - login

@Suite("YoiTVProviderAdapter.login")
struct YoiTVProviderAdapterLoginTests {
  @Test("Login success sets authenticated and rebuilds services")
  func loginSuccess() async throws {
    let mock = MockHTTPSession()
    mock.requestHandler = { _ in
      let response = HTTPURLResponse(
        url: URL(string: "http://test.com")!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(refreshedLoginJSON.utf8))
    }

    let adapter = makeAdapter(mock: mock)

    #expect(adapter.isAuthenticated == false)

    try await adapter.login(credentials: ["cid": "AABC538835997", "password": "testpass"])

    #expect(adapter.isAuthenticated == true)
    #expect(adapter.cid == "AABC538835997")
    #expect(adapter.accessToken == "refreshed_token")
  }

  @Test("Login with missing credentials throws")
  func loginMissingCredentials() async {
    let mock = MockHTTPSession()
    let adapter = makeAdapter(mock: mock)

    await #expect(throws: AuthError.self) {
      try await adapter.login(credentials: [:])
    }
  }
}

// MARK: - Stream requests

@Suite("YoiTVProviderAdapter.streamRequests")
struct YoiTVProviderAdapterStreamTests {
  @Test("liveStreamRequest returns nil when not authenticated")
  func liveStreamWithoutSession() {
    let mock = MockHTTPSession()
    let adapter = makeAdapter(mock: mock)

    let channel = ChannelDTO(
      id: "CH1", uid: nil, name: "NHK", description: nil, tags: nil,
      no: 1, timeshift: nil, timeshiftLen: nil, epgKeepDays: nil, state: nil,
      running: 1, playpath: "/nhk", liveType: nil
    )

    #expect(adapter.liveStreamRequest(for: channel) == nil)
  }

  @Test("liveStreamRequest returns valid request after login")
  func liveStreamAfterLogin() async throws {
    let mock = MockHTTPSession()
    mock.requestHandler = { _ in
      let response = HTTPURLResponse(
        url: URL(string: "http://test.com")!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(refreshedLoginJSON.utf8))
    }

    let adapter = makeAdapter(mock: mock)
    try await adapter.login(credentials: ["cid": "test", "password": "pass"])

    let channel = ChannelDTO(
      id: "CH1", uid: nil, name: "NHK", description: nil, tags: nil,
      no: 1, timeshift: nil, timeshiftLen: nil, epgKeepDays: nil, state: nil,
      running: 1, playpath: "/nhk", liveType: nil
    )

    let request = adapter.liveStreamRequest(for: channel)
    #expect(request != nil)
    #expect(request?.requiresProxy == true)
    #expect(request?.headers["Referer"] == "http://play.yoitv.com")
    #expect(request?.url.absoluteString.contains("type=live") == true)
  }

  @Test("vodStreamRequest returns nil for programs without VOD")
  func vodStreamNoPath() async throws {
    let mock = MockHTTPSession()
    mock.requestHandler = { _ in
      let response = HTTPURLResponse(
        url: URL(string: "http://test.com")!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(refreshedLoginJSON.utf8))
    }

    let adapter = makeAdapter(mock: mock)
    try await adapter.login(credentials: ["cid": "test", "password": "pass"])

    let program = ProgramDTO(time: 1000, title: "Live Only", path: "")
    #expect(adapter.vodStreamRequest(for: program) == nil)
  }

  @Test("vodStreamRequest returns valid request for VOD programs")
  func vodStreamWithPath() async throws {
    let mock = MockHTTPSession()
    mock.requestHandler = { _ in
      let response = HTTPURLResponse(
        url: URL(string: "http://test.com")!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(refreshedLoginJSON.utf8))
    }

    let adapter = makeAdapter(mock: mock)
    try await adapter.login(credentials: ["cid": "test", "password": "pass"])

    let program = ProgramDTO(time: 1000, title: "Past Show", path: "/query/past_show")
    let request = adapter.vodStreamRequest(for: program)

    #expect(request != nil)
    #expect(request?.requiresProxy == true)
    #expect(request?.url.absoluteString.contains("type=vod") == true)
  }
}

// MARK: - logout

@Suite("YoiTVProviderAdapter.logout")
struct YoiTVProviderAdapterLogoutTests {
  @Test("Logout clears session and stream requests return nil")
  func logoutClearsEverything() async throws {
    let mock = MockHTTPSession()
    mock.requestHandler = { _ in
      let response = HTTPURLResponse(
        url: URL(string: "http://test.com")!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(refreshedLoginJSON.utf8))
    }

    let adapter = makeAdapter(mock: mock)
    try await adapter.login(credentials: ["cid": "test", "password": "pass"])
    #expect(adapter.isAuthenticated == true)

    await adapter.logout()

    #expect(adapter.isAuthenticated == false)
    #expect(adapter.accessToken == nil)
    #expect(adapter.cid == nil)

    let channel = ChannelDTO(
      id: "CH1", uid: nil, name: "NHK", description: nil, tags: nil,
      no: 1, timeshift: nil, timeshiftLen: nil, epgKeepDays: nil, state: nil,
      running: 1, playpath: "/nhk", liveType: nil
    )
    #expect(adapter.liveStreamRequest(for: channel) == nil)
  }
}
