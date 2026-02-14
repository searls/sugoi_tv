import Foundation

/// Protocol for testability — all API calls go through this
public protocol APIClientProtocol: Sendable {
  func get<T: Decodable & Sendable>(
    url: URL,
    headers: [String: String]
  ) async throws -> T

  func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(
    url: URL,
    headers: [String: String],
    body: Body
  ) async throws -> Response
}

extension APIClientProtocol {
  public func get<T: Decodable & Sendable>(url: URL) async throws -> T {
    try await get(url: url, headers: [:])
  }
}

// MARK: - Errors

public enum APIError: Error, Sendable, Equatable {
  case invalidResponse
  case httpError(statusCode: Int)
  case authFailure(code: String)
}

// MARK: - Implementation

public actor APIClient: APIClientProtocol {
  private let session: URLSession
  private let decoder: JSONDecoder

  public init(session: URLSession = .shared) {
    self.session = session
    self.decoder = JSONDecoder()
  }

  public func get<T: Decodable & Sendable>(
    url: URL,
    headers: [String: String] = [:]
  ) async throws -> T {
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    for (key, value) in headers {
      request.setValue(value, forHTTPHeaderField: key)
    }
    return try await perform(request)
  }

  public func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(
    url: URL,
    headers: [String: String] = [:],
    body: Body
  ) async throws -> Response {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    for (key, value) in headers {
      request.setValue(value, forHTTPHeaderField: key)
    }
    request.httpBody = try JSONEncoder().encode(body)
    return try await perform(request)
  }

  private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw APIError.invalidResponse
    }
    guard (200...299).contains(http.statusCode) else {
      throw APIError.httpError(statusCode: http.statusCode)
    }
    return try decoder.decode(T.self, from: data)
  }
}

// MARK: - URL builders for YoiTV API endpoints

public enum YoiTVEndpoints {
  /// Login: `GET https://crm.yoitv.com/logon.sjs?...`
  public static func loginURL(cid: String, password: String, deviceID: String) -> URL {
    var components = URLComponents(string: "https://crm.yoitv.com/logon.sjs")!
    components.queryItems = [
      URLQueryItem(name: "from_app", value: "1"),
      URLQueryItem(name: "cid", value: cid),
      URLQueryItem(name: "password", value: password),
      URLQueryItem(name: "app_id", value: ""),
      URLQueryItem(name: "device_id", value: deviceID),
    ]
    return components.url!
  }

  /// Token refresh: `GET https://crm.yoitv.com/refresh.sjs?...`
  public static func refreshURL(refreshToken: String, cid: String, deviceID: String) -> URL {
    var components = URLComponents(string: "https://crm.yoitv.com/refresh.sjs")!
    components.queryItems = [
      URLQueryItem(name: "refresh_token", value: refreshToken),
      URLQueryItem(name: "cid", value: cid),
      URLQueryItem(name: "app_id", value: ""),
      URLQueryItem(name: "device_id", value: deviceID),
    ]
    return components.url!
  }

  /// Channel list: `GET {channelListHost}/api?action=listLives&...`
  public static func channelListURL(config: ProductConfig) -> URL {
    var components = URLComponents(string: "\(config.channelListHost)/api")!
    components.queryItems = [
      URLQueryItem(name: "action", value: "listLives"),
      URLQueryItem(name: "cid", value: config.vmsLiveCid),
      URLQueryItem(name: "uid", value: config.liveUid),
      URLQueryItem(name: "details", value: "0"),
      URLQueryItem(name: "page_size", value: "200"),
      URLQueryItem(name: "sort", value: "no asc"),
      URLQueryItem(name: "sort", value: "created_time desc"),
      URLQueryItem(name: "type", value: "video"),
      URLQueryItem(name: "no_epg", value: "1"),
      URLQueryItem(name: "referer", value: config.vmsReferer),
    ]
    return components.url!
  }

  /// Program guide for a specific channel: `GET {channelListHost}/api?action=listLives&vid={channelId}&no_epg=0&...`
  public static func epgURL(config: ProductConfig, channelID: String) -> URL {
    var components = URLComponents(string: "\(config.channelListHost)/api")!
    components.queryItems = [
      URLQueryItem(name: "action", value: "listLives"),
      URLQueryItem(name: "cid", value: config.vmsLiveCid),
      URLQueryItem(name: "uid", value: config.liveUid),
      URLQueryItem(name: "vid", value: channelID),
      URLQueryItem(name: "details", value: "0"),
      URLQueryItem(name: "page_size", value: "200"),
      URLQueryItem(name: "sort", value: "no asc"),
      URLQueryItem(name: "sort", value: "created_time desc"),
      URLQueryItem(name: "type", value: "video"),
      URLQueryItem(name: "no_epg", value: "0"),
      URLQueryItem(name: "epg_days", value: String(config.epgDays ?? 30)),
      URLQueryItem(name: "referer", value: config.vmsReferer),
    ]
    return components.url!
  }

  /// Single-play check: `GET {singleURL}?ua={ua}&own={own}&access_token={token}`
  public static func singlePlayURL(
    singleEndpoint: String,
    ua: String,
    own: Bool,
    accessToken: String
  ) -> URL {
    var components = URLComponents(string: singleEndpoint)!
    components.queryItems = [
      URLQueryItem(name: "ua", value: ua),
      URLQueryItem(name: "own", value: own ? "true" : "false"),
      URLQueryItem(name: "access_token", value: accessToken),
    ]
    return components.url!
  }

  /// CRM user data base URL
  public static func crmURL(controller: String, action: String) -> URL {
    var components = URLComponents(string: "https://crm.yoitv.com/tvum")!
    components.queryItems = [
      URLQueryItem(name: "controller", value: controller),
      URLQueryItem(name: "action", value: action),
    ]
    return components.url!
  }

  /// Bearer auth header for CRM API calls
  public static func bearerHeaders(accessToken: String) -> [String: String] {
    ["Authorization": "Bearer \(accessToken)"]
  }
}
