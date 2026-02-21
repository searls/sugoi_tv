import Foundation

/// A URLProtocol subclass that dispatches requests to per-session handlers
/// via the `X-Mock-Session` header. Each `MockHTTPSession` registers itself
/// and owns its handler + captured requests, eliminating shared mutable state.
public final class MockURLProtocol: URLProtocol, @unchecked Sendable {

  // MARK: - Session dispatch table

  private static let lock = NSLock()
  nonisolated(unsafe) private static var sessions: [String: MockHTTPSession] = [:]

  static func register(_ session: MockHTTPSession) {
    lock.lock()
    sessions[session.id] = session
    lock.unlock()
  }

  static func unregister(id: String) {
    lock.lock()
    sessions.removeValue(forKey: id)
    lock.unlock()
  }

  private static func session(for request: URLRequest) -> MockHTTPSession? {
    guard let id = request.allHTTPHeaderFields?["X-Mock-Session"]
      ?? request.value(forHTTPHeaderField: "X-Mock-Session")
    else { return nil }
    lock.lock()
    defer { lock.unlock() }
    return sessions[id]
  }

  // MARK: - URLProtocol overrides

  override public class func canInit(with request: URLRequest) -> Bool {
    true
  }

  override public class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override public func startLoading() {
    guard let mockSession = Self.session(for: request) else {
      client?.urlProtocol(self, didFailWithError: MockURLProtocolError.noHandler)
      return
    }

    mockSession.appendRequest(request)

    guard let handler = mockSession.requestHandler else {
      client?.urlProtocol(self, didFailWithError: MockURLProtocolError.noHandler)
      return
    }

    do {
      let (response, data) = try handler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override public func stopLoading() {}
}

public enum MockURLProtocolError: Error {
  case noHandler
  case unmatchedRequest(URLRequest)
}

// MARK: - Route-based handler builder

/// Builds a request handler that matches URLs by path prefix and returns fixture data
public struct MockRouter: Sendable {
  public typealias Route = @Sendable (URLRequest) throws -> (Int, Data)

  private var routes: [@Sendable (URLRequest) -> (Int, Data)?] = []

  public init() {}

  /// Register a route matching a URL path containing the given string
  public mutating func on(
    pathContaining substring: String,
    statusCode: Int = 200,
    body: Data
  ) {
    routes.append { request in
      guard let url = request.url, url.absoluteString.contains(substring) else {
        return nil
      }
      return (statusCode, body)
    }
  }

  /// Register a route matching a URL path containing the given string with a JSON fixture
  public mutating func on(
    pathContaining substring: String,
    statusCode: Int = 200,
    jsonFixture: String
  ) {
    let data = jsonFixture.data(using: .utf8) ?? Data()
    on(pathContaining: substring, statusCode: statusCode, body: data)
  }

  /// Build the request handler for use with MockHTTPSession
  public func handler() -> @Sendable (URLRequest) throws -> (HTTPURLResponse, Data) {
    let capturedRoutes = routes
    return { request in
      for route in capturedRoutes {
        if let (statusCode, data) = route(request) {
          let response = HTTPURLResponse(
            url: request.url!, statusCode: statusCode,
            httpVersion: "HTTP/1.1", headerFields: nil
          )!
          return (response, data)
        }
      }
      throw MockURLProtocolError.unmatchedRequest(request)
    }
  }
}
