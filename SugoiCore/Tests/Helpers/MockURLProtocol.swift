import Foundation

/// A URLProtocol subclass that intercepts all requests and returns mock responses.
/// Use `MockURLProtocol.requestHandler` to provide responses per-test.
public final class MockURLProtocol: URLProtocol, @unchecked Sendable {

  /// Handler called for every intercepted request. Set this in your test setUp.
  /// Return (HTTPURLResponse, Data) or throw to simulate an error.
  nonisolated(unsafe) public static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

  /// All requests captured during the test (for assertions)
  nonisolated(unsafe) private static var _requests: [URLRequest] = []
  private static let lock = NSLock()

  public static var capturedRequests: [URLRequest] {
    lock.lock()
    defer { lock.unlock() }
    return _requests
  }

  public static func reset() {
    lock.lock()
    _requests.removeAll()
    lock.unlock()
    requestHandler = nil
  }

  // MARK: - URLProtocol overrides

  override public class func canInit(with request: URLRequest) -> Bool {
    true
  }

  override public class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override public func startLoading() {
    Self.lock.lock()
    Self._requests.append(request)
    Self.lock.unlock()

    guard let handler = Self.requestHandler else {
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

// MARK: - URLSession convenience

extension URLSession {
  /// Create a URLSession configured to use MockURLProtocol
  public static func mock() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
  }
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

  /// Build the request handler for use with MockURLProtocol
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
