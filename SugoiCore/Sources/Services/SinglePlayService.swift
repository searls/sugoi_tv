import Foundation

/// Manages single-play enforcement by polling the YoiTV single.sjs endpoint
public actor SinglePlayService {
  private let apiClient: any APIClientProtocol
  private var pollingTask: Task<Void, Never>?

  public private(set) var isOwning: Bool = false

  public init(apiClient: any APIClientProtocol) {
    self.apiClient = apiClient
  }

  /// Check if we currently own the playback slot
  public func checkOwnership(
    singleEndpoint: String,
    accessToken: String,
    ua: String,
    own: Bool
  ) async throws -> Bool {
    let url = YoiTVEndpoints.singlePlayURL(
      singleEndpoint: singleEndpoint,
      ua: ua,
      own: own,
      accessToken: accessToken
    )
    let response: SinglePlayResponse = try await apiClient.get(url: url)
    isOwning = response.own
    return response.own
  }

  /// Start periodic ownership polling during playback
  public func startPolling(
    singleEndpoint: String,
    accessToken: String,
    ua: String,
    intervalSeconds: TimeInterval = 30
  ) {
    stopPolling()
    pollingTask = Task { [weak self] in
      while !Task.isCancelled {
        _ = try? await self?.checkOwnership(
          singleEndpoint: singleEndpoint,
          accessToken: accessToken,
          ua: ua,
          own: true
        )
        try? await Task.sleep(for: .seconds(intervalSeconds))
      }
    }
  }

  public func stopPolling() {
    pollingTask?.cancel()
    pollingTask = nil
    isOwning = false
  }

  /// Platform-appropriate user agent string
  public static var platformUA: String {
    #if os(iOS)
    return "ios"
    #elseif os(macOS)
    return "macos"
    #elseif os(tvOS)
    return "tvos"
    #else
    return "ios"
    #endif
  }
}
