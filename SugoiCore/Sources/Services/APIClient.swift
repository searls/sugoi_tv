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
