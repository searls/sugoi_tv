import Foundation

/// Thread-safe box for capturing a value from a mock request handler.
public final class StateCapture: @unchecked Sendable {
  private let lock = NSLock()
  private var _value: Bool?

  public init() {}

  public func set(_ value: Bool) {
    lock.lock()
    _value = value
    lock.unlock()
  }

  public var value: Bool? {
    lock.lock()
    defer { lock.unlock() }
    return _value
  }
}

/// Thread-safe call counter for use in mock request handlers.
public final class CallCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var _count = 0

  public init() {}

  /// Increments the counter and returns the new value.
  @discardableResult
  public func increment() -> Int {
    lock.lock()
    defer { lock.unlock() }
    _count += 1
    return _count
  }

  public var count: Int {
    lock.lock()
    defer { lock.unlock() }
    return _count
  }
}

/// A per-test mock HTTP session that eliminates shared mutable state.
///
/// Each instance gets its own `requestHandler` and `capturedRequests`,
/// dispatched via an `X-Mock-Session` header injected into the URLSession config.
/// This allows all networking tests to run in parallel.
public final class MockHTTPSession: @unchecked Sendable {
  let id = UUID().uuidString

  /// The URLSession configured to route through this mock session.
  public let session: URLSession

  private let lock = NSLock()

  /// Handler called for every intercepted request.
  /// Return (HTTPURLResponse, Data) or throw to simulate an error.
  public var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

  private var _capturedRequests: [URLRequest] = []

  /// All requests captured during the test (for assertions).
  public var capturedRequests: [URLRequest] {
    lock.lock()
    defer { lock.unlock() }
    return _capturedRequests
  }

  func appendRequest(_ request: URLRequest) {
    lock.lock()
    _capturedRequests.append(request)
    lock.unlock()
  }

  public init() {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    config.httpAdditionalHeaders = ["X-Mock-Session": id]
    session = URLSession(configuration: config)
    MockURLProtocol.register(self)
  }

  deinit {
    MockURLProtocol.unregister(id: id)
  }
}
