import Foundation
import Network

/// A local HTTP reverse proxy that injects the `Referer` header into upstream
/// requests. This enables AirPlay external playback — the Apple TV fetches HLS
/// segments from *this* proxy (reachable on the LAN), and the proxy adds the
/// header the VMS server requires before forwarding.
///
/// When the proxy can't start (no network, port conflict), callers fall back to
/// direct URLs with `AVURLAssetHTTPHeaderFieldsKey` (works locally, not AirPlay).
@MainActor
public final class RefererProxy {
  /// The referer value injected into every upstream request.
  private let referer: String

  /// NWListener bound to 0.0.0.0 on an ephemeral port.
  nonisolated(unsafe) private var listener: NWListener?

  /// The port the listener is actually bound to (set once ready).
  public private(set) var port: UInt16?

  /// Whether the proxy is accepting connections.
  public private(set) var isReady = false

  /// URLSession for upstream fetches (no redirects followed — we rewrite them).
  private let upstream: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.httpShouldSetCookies = false
    return URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
  }()

  public init(referer: String) {
    self.referer = referer
  }

  // MARK: - Lifecycle

  /// Start listening. Non-blocking — returns immediately.
  public func start() {
    guard listener == nil else { return }
    do {
      let params = NWParameters.tcp
      let listener = try NWListener(using: params, on: .any)
      self.listener = listener
      let referer = self.referer

      listener.stateUpdateHandler = { [weak self] state in
        Task { @MainActor in
          switch state {
          case .ready:
            self?.port = listener.port?.rawValue
            self?.isReady = true
          case .failed(_):
            self?.isReady = false
            self?.port = nil
          case .cancelled:
            self?.isReady = false
            self?.port = nil
          default:
            break
          }
        }
      }

      listener.newConnectionHandler = { [weak self] connection in
        self?.handleConnection(connection, referer: referer)
      }

      listener.start(queue: .global(qos: .userInitiated))
    } catch {
      isReady = false

    }
  }

  public func stop() {
    listener?.cancel()
    listener = nil
    isReady = false
    port = nil
  }

  // MARK: - URL mapping

  /// The LAN IPv4 address of this machine (for constructing proxy URLs).
  public nonisolated var localIP: String? {
    Self.localIPAddress()
  }

  /// Wrap a real stream URL through the proxy.
  /// Returns `nil` if the proxy isn't ready or the URL can't be mapped.
  public func proxiedURL(for original: URL) -> URL? {
    guard isReady, let port, let ip = localIP else { return nil }
    return Self.buildProxiedURL(original: original, proxyHost: ip, proxyPort: port)
  }

  /// Pure function: build a proxied URL from components.
  /// Layout: `http://{proxyHost}:{proxyPort}/{upstreamHost}:{upstreamPort}{path}?{query}`
  /// The upstream host:port is embedded in the path prefix so relative HLS
  /// segment URLs (e.g. `segments/001.ts`) resolve back through the proxy
  /// with the correct upstream directory structure.
  nonisolated static func buildProxiedURL(original: URL, proxyHost: String, proxyPort: UInt16) -> URL? {
    guard let scheme = original.scheme,
          let host = original.host(percentEncoded: false) else { return nil }

    let upstreamPort = original.port ?? (scheme == "https" ? 443 : 80)
    let path = original.path(percentEncoded: true)

    // Build directly as a string to avoid URLComponents encoding the query
    var urlString = "http://\(proxyHost):\(proxyPort)/\(host):\(upstreamPort)\(path)"
    if let query = original.query(percentEncoded: true) {
      urlString += "?\(query)"
    }
    return URL(string: urlString)
  }

  /// Reconstruct the original upstream URL from a proxy request path.
  /// Input path: `/host:port/rest/of/path` (query string separate).
  nonisolated static func targetURL(fromPath path: String, query: String?) -> URL? {
    // Strip leading "/"
    var stripped = path
    if stripped.hasPrefix("/") { stripped = String(stripped.dropFirst()) }
    guard !stripped.isEmpty else { return nil }

    var urlString = "http://\(stripped)"
    if let query, !query.isEmpty {
      urlString += "?\(query)"
    }
    return URL(string: urlString)
  }

  // MARK: - HLS manifest rewriting

  /// Rewrite absolute `http://` URLs in an HLS manifest to route through the proxy.
  nonisolated static func rewriteManifest(
    _ body: String,
    proxyHost: String,
    proxyPort: UInt16
  ) -> String {
    var result = ""
    result.reserveCapacity(body.count)
    for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
      let rewritten = rewriteAbsoluteURLsInLine(String(line), proxyHost: proxyHost, proxyPort: proxyPort)
      result += rewritten + "\n"
    }
    // Remove trailing newline if original didn't have one
    if !body.hasSuffix("\n") && result.hasSuffix("\n") {
      result.removeLast()
    }
    return result
  }

  /// Rewrite any `http://...` URL found in a single line.
  private nonisolated static func rewriteAbsoluteURLsInLine(
    _ line: String,
    proxyHost: String,
    proxyPort: UInt16
  ) -> String {
    // Skip comments/tags that don't contain URLs we need to rewrite
    // But some EXT tags do contain URIs, so only skip pure comments
    guard line.contains("http://") || line.contains("https://") else {
      return line
    }

    var result = ""
    var remaining = line[...]
    while !remaining.isEmpty {
      // Find the next http:// or https:// URL
      var foundRange: Range<Substring.Index>?
      for prefix in ["http://", "https://"] {
        if let r = remaining.range(of: prefix) {
          if foundRange == nil || r.lowerBound < foundRange!.lowerBound {
            foundRange = r
          }
        }
      }
      guard let urlStart = foundRange?.lowerBound else {
        result += remaining
        break
      }

      // Append text before the URL
      result += remaining[remaining.startIndex..<urlStart]

      // Find the end of the URL (whitespace, quote, or end of string)
      let afterPrefix = foundRange!.upperBound
      var urlEnd = remaining.endIndex
      for idx in remaining[afterPrefix...].indices {
        let ch = remaining[idx]
        if ch == " " || ch == "\t" || ch == "\"" || ch == "'" || ch == ">" {
          urlEnd = idx
          break
        }
      }

      let urlString = String(remaining[urlStart..<urlEnd])
      if let originalURL = URL(string: urlString),
         let proxied = buildProxiedURL(original: originalURL, proxyHost: proxyHost, proxyPort: proxyPort) {
        result += proxied.absoluteString
      } else {
        result += urlString
      }
      remaining = remaining[urlEnd...]
    }
    return result
  }

  /// Rewrite a Location header value through the proxy.
  nonisolated static func rewriteRedirectLocation(
    _ location: String,
    proxyHost: String,
    proxyPort: UInt16
  ) -> String? {
    guard let url = URL(string: location),
          let proxied = buildProxiedURL(original: url, proxyHost: proxyHost, proxyPort: proxyPort) else {
      return nil
    }
    return proxied.absoluteString
  }

  // MARK: - Connection handling

  private nonisolated func handleConnection(_ connection: NWConnection, referer: String) {
    connection.start(queue: .global(qos: .userInitiated))
    // Read the HTTP request (up to 64KB should be plenty for an HLS request line + headers)
    connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
      guard let self, let data, error == nil else {
        connection.cancel()
        return
      }
      self.processRequest(data: data, connection: connection, referer: referer)
    }
  }

  private nonisolated func processRequest(data: Data, connection: NWConnection, referer: String) {
    guard let requestString = String(data: data, encoding: .utf8) else {
      sendError(connection: connection, status: 400, message: "Bad Request")
      return
    }

    // Parse the request line: "GET /path HTTP/1.1\r\n..."
    let lines = requestString.split(separator: "\r\n", maxSplits: 1)
    guard let requestLine = lines.first else {
      sendError(connection: connection, status: 400, message: "Bad Request")
      return
    }

    let parts = requestLine.split(separator: " ", maxSplits: 2)
    guard parts.count >= 2 else {
      sendError(connection: connection, status: 400, message: "Bad Request")
      return
    }

    let rawPathAndQuery = String(parts[1])

    // Split path and query
    let path: String
    let query: String?
    if let qIndex = rawPathAndQuery.firstIndex(of: "?") {
      path = String(rawPathAndQuery[..<qIndex])
      query = String(rawPathAndQuery[rawPathAndQuery.index(after: qIndex)...])
    } else {
      path = rawPathAndQuery
      query = nil
    }

    guard let targetURL = Self.targetURL(fromPath: path, query: query) else {
      sendError(connection: connection, status: 400, message: "Cannot resolve target URL")
      return
    }

    // Fetch upstream with Referer header
    var request = URLRequest(url: targetURL)
    request.setValue(referer, forHTTPHeaderField: "Referer")

    let proxyHost: String
    let proxyPort: UInt16
    if let listener = self.listener, let lPort = listener.port?.rawValue,
       let ip = Self.localIPAddress() {
      proxyHost = ip
      proxyPort = lPort
    } else {
      sendError(connection: connection, status: 502, message: "Proxy not ready")
      return
    }

    let task = upstream.dataTask(with: request) { [weak self] data, response, error in
      guard let self else {
        connection.cancel()
        return
      }

      guard let httpResponse = response as? HTTPURLResponse else {
        self.sendError(connection: connection, status: 502, message: error?.localizedDescription ?? "Upstream error")
        return
      }

      let statusCode = httpResponse.statusCode

      // Handle redirects: rewrite Location and return the redirect to the client
      if (300...399).contains(statusCode), let location = httpResponse.value(forHTTPHeaderField: "Location") {
        let rewritten = Self.rewriteRedirectLocation(location, proxyHost: proxyHost, proxyPort: proxyPort) ?? location
        let header = "HTTP/1.1 \(statusCode) Redirect\r\nLocation: \(rewritten)\r\nConnection: close\r\n\r\n"
        self.sendAndClose(connection: connection, data: Data(header.utf8))
        return
      }

      guard let data else {
        self.sendError(connection: connection, status: 502, message: "No data from upstream")
        return
      }

      // Check if this is an HLS manifest that needs URL rewriting
      let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
      let isManifest = targetURL.path(percentEncoded: false).lowercased().hasSuffix(".m3u8")
        || contentType.contains("mpegurl")
        || contentType.contains("x-mpegURL")

      let responseData: Data
      let responseContentType: String
      if isManifest, let body = String(data: data, encoding: .utf8) {
        let rewritten = Self.rewriteManifest(body, proxyHost: proxyHost, proxyPort: proxyPort)
        responseData = Data(rewritten.utf8)
        responseContentType = "application/vnd.apple.mpegurl"
      } else {
        responseData = data
        responseContentType = contentType.isEmpty ? "application/octet-stream" : contentType
      }

      var header = "HTTP/1.1 \(statusCode) OK\r\n"
      header += "Content-Type: \(responseContentType)\r\n"
      header += "Content-Length: \(responseData.count)\r\n"
      header += "Connection: close\r\n"
      header += "Access-Control-Allow-Origin: *\r\n"
      header += "\r\n"

      var fullResponse = Data(header.utf8)
      fullResponse.append(responseData)
      self.sendAndClose(connection: connection, data: fullResponse)
    }
    task.resume()
  }

  private nonisolated func sendError(connection: NWConnection, status: Int, message: String) {
    let body = message
    let header = "HTTP/1.1 \(status) \(message)\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n"
    sendAndClose(connection: connection, data: Data((header + body).utf8))
  }

  private nonisolated func sendAndClose(connection: NWConnection, data: Data) {
    connection.send(content: data, completion: .contentProcessed { _ in
      connection.cancel()
    })
  }

  // MARK: - Network utilities

  /// Discover the LAN IPv4 address by inspecting network interfaces.
  nonisolated static func localIPAddress() -> String? {
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
    defer { freeifaddrs(ifaddr) }

    var bestIP: String?
    for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
      let interface = ptr.pointee
      let family = interface.ifa_addr.pointee.sa_family
      guard family == UInt8(AF_INET) else { continue } // IPv4 only

      let name = String(validatingCString: interface.ifa_name) ?? ""
      guard name.hasPrefix("en") else { continue } // Wi-Fi / Ethernet

      var addr = interface.ifa_addr.pointee
      var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      if getnameinfo(&addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                      &hostname, socklen_t(hostname.count),
                      nil, 0, NI_NUMERICHOST) == 0 {
        let ip = hostname.withUnsafeBufferPointer { buf in
          String(validatingCString: buf.baseAddress!) ?? ""
        }
        if !ip.hasPrefix("127.") {
          bestIP = ip
          // Prefer en0 (Wi-Fi on Mac) but accept others
          if name == "en0" { return ip }
        }
      }
    }
    return bestIP
  }
}

// MARK: - URLSession delegate that prevents redirect following

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    // Don't follow redirects — we rewrite Location headers instead
    completionHandler(nil)
  }
}
