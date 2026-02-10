import Foundation

enum APIError: Error, LocalizedError {
  case httpError(Int)
  case authRequired
  case invalidResponse
  case decodingError(Error)

  var errorDescription: String? {
    switch self {
    case .httpError(let code): "HTTP error \(code)"
    case .authRequired: "Authentication required"
    case .invalidResponse: "Invalid server response"
    case .decodingError(let error): "Decoding error: \(error.localizedDescription)"
    }
  }
}

enum AuthError: Error, LocalizedError {
  case invalidCredentials
  case accountExpired
  case accountDisabled
  case missingFields
  case serverError(String)

  var errorDescription: String? {
    switch self {
    case .invalidCredentials: "Invalid customer ID or password"
    case .accountExpired: "Your subscription has expired"
    case .accountDisabled: "Your account has been disabled"
    case .missingFields: "Incomplete server response"
    case .serverError(let code): "Server error: \(code)"
    }
  }
}

actor APIClient {
  static let shared = APIClient()

  private let session = URLSession.shared
  private let decoder = JSONDecoder()

  // MARK: - Auth

  func login(cid: String, password: String, deviceId: String) async throws -> LoginResponse {
    var components = URLComponents(string: "https://crm.yoitv.com/logon.sjs")!
    components.queryItems = [
      URLQueryItem(name: "from_app", value: "1"),
      URLQueryItem(name: "cid", value: cid),
      URLQueryItem(name: "password", value: password),
      URLQueryItem(name: "app_id", value: ""),
      URLQueryItem(name: "device_id", value: deviceId),
    ]
    return try await get(components.url!, as: LoginResponse.self)
  }

  func refresh(refreshToken: String, cid: String, deviceId: String) async throws -> LoginResponse {
    var components = URLComponents(string: "https://crm.yoitv.com/refresh.sjs")!
    components.queryItems = [
      URLQueryItem(name: "refresh_token", value: refreshToken),
      URLQueryItem(name: "cid", value: cid),
      URLQueryItem(name: "app_id", value: ""),
      URLQueryItem(name: "device_id", value: deviceId),
    ]
    return try await get(components.url!, as: LoginResponse.self)
  }

  // MARK: - Channels & EPG

  func fetchChannels(
    host: String, cid: String, uid: String, referer: String
  ) async throws -> ChannelListResponse {
    var components = URLComponents(string: "\(host)/api")!
    components.queryItems = [
      URLQueryItem(name: "action", value: "listLives"),
      URLQueryItem(name: "cid", value: cid),
      URLQueryItem(name: "uid", value: uid),
      URLQueryItem(name: "details", value: "0"),
      URLQueryItem(name: "page_size", value: "200"),
      URLQueryItem(name: "sort", value: "no asc"),
      URLQueryItem(name: "sort", value: "created_time desc"),
      URLQueryItem(name: "type", value: "video"),
      URLQueryItem(name: "no_epg", value: "1"),
      URLQueryItem(name: "referer", value: referer),
    ]
    return try await get(components.url!, as: ChannelListResponse.self)
  }

  func fetchEPG(
    host: String, cid: String, uid: String, channelId: String,
    referer: String, days: Int = 30
  ) async throws -> ChannelListResponse {
    var components = URLComponents(string: "\(host)/api")!
    components.queryItems = [
      URLQueryItem(name: "action", value: "listLives"),
      URLQueryItem(name: "cid", value: cid),
      URLQueryItem(name: "uid", value: uid),
      URLQueryItem(name: "vid", value: channelId),
      URLQueryItem(name: "details", value: "0"),
      URLQueryItem(name: "page_size", value: "200"),
      URLQueryItem(name: "sort", value: "no asc"),
      URLQueryItem(name: "sort", value: "created_time desc"),
      URLQueryItem(name: "type", value: "video"),
      URLQueryItem(name: "no_epg", value: "0"),
      URLQueryItem(name: "epg_days", value: String(days)),
      URLQueryItem(name: "referer", value: referer),
    ]
    return try await get(components.url!, as: ChannelListResponse.self)
  }

  // MARK: - Single Play

  func checkSinglePlay(
    url: String, ua: String, own: Bool, accessToken: String
  ) async throws -> SinglePlayResponse {
    var components = URLComponents(string: url)!
    components.queryItems = [
      URLQueryItem(name: "ua", value: ua),
      URLQueryItem(name: "own", value: own ? "true" : "false"),
      URLQueryItem(name: "access_token", value: accessToken),
    ]
    return try await get(components.url!, as: SinglePlayResponse.self)
  }

  // MARK: - User Data (Bearer auth)

  func fetchPlayRecords(accessToken: String) async throws -> PlayRecordListResponse {
    let url = URL(
      string:
        "https://crm.yoitv.com/tvum?controller=tvum_favorite&action=listPlayRecord")!
    return try await getWithAuth(url, token: accessToken, as: PlayRecordListResponse.self)
  }

  func syncPlayRecord(accessToken: String, payload: SyncPlayRecordPayload) async throws {
    let url = URL(
      string:
        "https://crm.yoitv.com/tvum?controller=tvum_favorite&action=syncPlayRecord")!
    try await postWithAuth(url, token: accessToken, body: payload)
  }

  // MARK: - HTTP primitives

  private func get<T: Decodable & Sendable>(_ url: URL, as _: T.Type) async throws -> T {
    let (data, response) = try await session.data(from: url)
    try validateHTTPResponse(response)
    do {
      return try decoder.decode(T.self, from: data)
    } catch {
      throw APIError.decodingError(error)
    }
  }

  private func getWithAuth<T: Decodable & Sendable>(
    _ url: URL, token: String, as _: T.Type
  ) async throws -> T {
    var request = URLRequest(url: url)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    let (data, response) = try await session.data(for: request)
    try validateHTTPResponse(response)
    do {
      return try decoder.decode(T.self, from: data)
    } catch {
      throw APIError.decodingError(error)
    }
  }

  private func postWithAuth<T: Encodable & Sendable>(
    _ url: URL, token: String, body: T
  ) async throws {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(body)
    let (_, response) = try await session.data(for: request)
    try validateHTTPResponse(response)
  }

  private func validateHTTPResponse(_ response: URLResponse) throws {
    guard let http = response as? HTTPURLResponse else {
      throw APIError.invalidResponse
    }
    guard (200...299).contains(http.statusCode) else {
      throw APIError.httpError(http.statusCode)
    }
  }
}
