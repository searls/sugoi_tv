import Foundation
import SugoiCore
import Synchronization

/// A free IPTV provider that loads channels from M3U playlists and
/// program guides from XMLTV feeds hosted by iptv-org.
public final class IPTVProvider: TVProvider, @unchecked Sendable {
  public let displayName = "IPTV"
  public let providerID = "iptv"
  public let requiresAuthentication = false
  public var displayTimezone: TimeZone { .current }

  public static let defaultM3UURL = "https://iptv-org.github.io/iptv/index.m3u"

  private static let m3uURLKey = "iptv_m3u_url"

  private let lock = NSLock()
  private var m3uURL: String = ""
  private var parsedChannels: [M3UChannel] = []
  private var logoURLs: [String: URL] = [:]
  private var streamURLs: [String: URL] = [:]
  private var epgURL: URL?
  private var epgData: [String: [XMLTVProgram]] = [:]
  private var _isConfigured: Bool = false

  // Override for testing — allows injecting data without network
  private var _urlSession: URLSession
  var overrideM3UData: String?
  var overrideEPGData: Data?

  public init(urlSession: URLSession = .shared) {
    self._urlSession = urlSession
  }

  // MARK: - TVProvider

  public var isAuthenticated: Bool {
    lock.withLock { _isConfigured }
  }

  public var loginFields: [LoginField] {
    [
      LoginField(
        key: "m3u_url",
        label: "M3U Playlist URL",
        contentType: .url,
        defaultValue: Self.defaultM3UURL
      ),
    ]
  }

  public func login(credentials: [String: String]) async throws {
    let urlString = credentials["m3u_url"] ?? Self.defaultM3UURL
    try await loadPlaylist(from: urlString)
    UserDefaults.standard.set(urlString, forKey: Self.m3uURLKey)
  }

  public func restoreSession() async throws -> Bool {
    guard let savedURL = UserDefaults.standard.string(forKey: Self.m3uURLKey) else {
      return false
    }
    do {
      try await loadPlaylist(from: savedURL)
      return true
    } catch {
      return false
    }
  }

  public func logout() async {
    lock.withLock {
      _isConfigured = false
      parsedChannels = []
      logoURLs = [:]
      streamURLs = [:]
      epgURL = nil
      epgData = [:]
      m3uURL = ""
    }
    UserDefaults.standard.removeObject(forKey: Self.m3uURLKey)
  }

  public func startAutoRefresh() async {}

  public func reauthenticate() async throws -> Bool {
    lock.withLock { _isConfigured }
  }

  // MARK: - Channels

  public func fetchChannels() async throws -> [ChannelDTO] {
    let channels = lock.withLock { parsedChannels }
    return channels.map { m3u in
      ChannelDTO(
        id: m3u.id,
        name: m3u.name,
        tags: "$LIVE_CAT_\(m3u.group)",
        no: m3u.channelNumber,
        playpath: m3u.streamURL.absoluteString
      )
    }
  }

  public func groupByCategory(_ channels: [ChannelDTO]) -> [(category: String, channels: [ChannelDTO])] {
    channels.groupedByCategory(order: [])
  }

  public func thumbnailURL(for channel: ChannelDTO) -> URL? {
    lock.withLock { logoURLs[channel.id] }
  }

  // MARK: - Programs

  public func fetchPrograms(channelID: String) async throws -> [ProgramDTO] {
    let needsLoad = lock.withLock { epgData.isEmpty && epgURL != nil }
    if needsLoad {
      try await loadEPG()
    }
    let programs = lock.withLock { epgData[channelID] ?? [] }
    return programs.map { xmltv in
      ProgramDTO(
        time: Int(xmltv.start.timeIntervalSince1970),
        title: xmltv.title,
        path: ""
      )
    }
  }

  // MARK: - Streaming

  public func liveStreamRequest(for channel: ChannelDTO) -> StreamRequest? {
    guard let url = lock.withLock({ streamURLs[channel.id] }) else { return nil }
    return StreamRequest(url: url, headers: [:], requiresProxy: false)
  }

  public func vodStreamRequest(for program: ProgramDTO) -> StreamRequest? {
    nil
  }

  // MARK: - Private

  private func loadPlaylist(from urlString: String) async throws {
    let content: String
    if let override = overrideM3UData {
      content = override
    } else {
      guard let url = URL(string: urlString) else {
        throw URLError(.badURL)
      }
      let (data, _) = try await _urlSession.data(from: url)
      guard let text = String(data: data, encoding: .utf8) else {
        throw URLError(.cannotDecodeContentData)
      }
      content = text
    }

    let result = M3UParser.parse(content)

    lock.withLock {
      m3uURL = urlString
      parsedChannels = result.channels
      epgURL = result.epgURL
      logoURLs = [:]
      streamURLs = [:]
      for channel in result.channels {
        if let logo = channel.logoURL {
          logoURLs[channel.id] = logo
        }
        streamURLs[channel.id] = channel.streamURL
      }
      _isConfigured = !result.channels.isEmpty
    }
  }

  private func loadEPG() async throws {
    let url = lock.withLock { epgURL }
    guard let epgURL = url else { return }

    let data: Data
    if let override = overrideEPGData {
      data = override
    } else {
      let (downloaded, _) = try await _urlSession.data(from: epgURL)
      data = downloaded
    }

    let parsed = XMLTVParser.parse(data)
    lock.withLock {
      epgData = parsed
    }
  }
}
