import Foundation

// MARK: - TVProvider protocol

/// Abstraction over a TV streaming service (YoiTV, IPTV, etc.)
/// Providers manage their own authentication, channel fetching, program guides,
/// and stream URL construction.
public protocol TVProvider: AnyObject, Sendable {
  /// Human-readable name shown in the UI (e.g. "YoiTV", "IPTV")
  var displayName: String { get }

  /// Stable identifier for persistence (e.g. "yoitv", "iptv")
  var providerID: String { get }

  /// Whether this provider requires credentials before use.
  /// When false, the app skips the login screen entirely.
  var requiresAuthentication: Bool { get }

  /// Timezone used for displaying program times.
  /// YoiTV uses Asia/Tokyo; IPTV uses the local timezone.
  var displayTimezone: TimeZone { get }

  /// Whether the provider currently has a valid session.
  var isAuthenticated: Bool { get async }

  // MARK: - Authentication

  /// Describes the fields needed for the login form.
  var loginFields: [LoginField] { get }

  /// Authenticate with the given credentials.
  /// Keys in the dictionary match `LoginField.key`.
  func login(credentials: [String: String]) async throws

  /// Attempt to restore a previous session from persistent storage.
  /// Returns true if a session was restored.
  func restoreSession() async throws -> Bool

  /// Sign out and clear stored credentials.
  func logout() async

  /// Start background token refresh (if applicable).
  func startAutoRefresh() async

  /// Attempt silent re-authentication using stored credentials.
  /// Returns true if re-auth succeeded.
  func reauthenticate() async throws -> Bool

  // MARK: - Channels

  /// Fetch the full channel list.
  func fetchChannels() async throws -> [ChannelDTO]

  /// Group channels by category in the provider's preferred order.
  func groupByCategory(_ channels: [ChannelDTO]) -> [(category: String, channels: [ChannelDTO])]

  /// Thumbnail URL for a channel, or nil if unavailable.
  func thumbnailURL(for channel: ChannelDTO) -> URL?

  // MARK: - Programs

  /// Fetch program guide entries for a specific channel.
  func fetchPrograms(channelID: String) async throws -> [ProgramDTO]

  // MARK: - Streaming

  /// Build a stream request for live playback, or nil if unavailable.
  func liveStreamRequest(for channel: ChannelDTO) -> StreamRequest?

  /// Build a stream request for VOD playback, or nil if unavailable.
  func vodStreamRequest(for program: ProgramDTO) -> StreamRequest?

  // MARK: - Playback enforcement (optional)

  /// Start single-play enforcement polling (YoiTV-specific).
  func startPlaybackEnforcement() async

  /// Stop single-play enforcement polling.
  func stopPlaybackEnforcement() async
}

// MARK: - Default implementations for optional methods

public extension TVProvider {
  func startPlaybackEnforcement() async {}
  func stopPlaybackEnforcement() async {}
  func startAutoRefresh() async {}
}

// MARK: - StreamRequest

/// Describes everything needed to load a stream: URL, HTTP headers, and
/// whether a local referer proxy is required (for AirPlay compatibility).
public struct StreamRequest: Sendable {
  public let url: URL
  public let headers: [String: String]
  public let requiresProxy: Bool

  public init(url: URL, headers: [String: String] = [:], requiresProxy: Bool = false) {
    self.url = url
    self.headers = headers
    self.requiresProxy = requiresProxy
  }
}

// MARK: - LoginField

/// Describes a single input field in the provider's login form.
public struct LoginField: Sendable, Identifiable {
  public let key: String
  public let label: String
  public let isSecure: Bool
  public let contentType: ContentType
  public let defaultValue: String

  public var id: String { key }

  public enum ContentType: Sendable {
    case username
    case password
    case url
    case text
  }

  public init(
    key: String,
    label: String,
    isSecure: Bool = false,
    contentType: ContentType = .text,
    defaultValue: String = ""
  ) {
    self.key = key
    self.label = label
    self.isSecure = isSecure
    self.contentType = contentType
    self.defaultValue = defaultValue
  }
}
