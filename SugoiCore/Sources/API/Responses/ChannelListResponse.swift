import Foundation

/// Response from `listLives` with `no_epg=1`
public struct ChannelListResponse: Codable, Sendable {
  public let result: [ChannelDTO]
  public let code: String
}

/// A single channel as returned by the VMS API
public struct ChannelDTO: Codable, Sendable, Hashable, Identifiable {
  public let id: String
  public let uid: String?
  public let name: String
  public let description: String?
  public let tags: String?
  public let no: Int
  public let timeshift: Int?
  public let timeshiftLen: Int?
  public let epgKeepDays: Int?
  public let state: Int?
  public let running: Int?
  public let playpath: String
  public let liveType: String?

  enum CodingKeys: String, CodingKey {
    case id, uid, name, description, tags, no, timeshift
    case timeshiftLen = "timeshift_len"
    case epgKeepDays = "epg_keep_days"
    case state, running, playpath
    case liveType = "live_type"
  }

  /// Extract category names from the `$LIVE_CAT_` prefixed tags
  public var categories: [String] {
    guard let tags else { return [] }
    return tags.split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { $0.hasPrefix("$LIVE_CAT_") }
      .map { String($0.dropFirst("$LIVE_CAT_".count)) }
  }

  /// Primary display category, defaulting to "Others"
  public var primaryCategory: String {
    categories.first ?? "Others"
  }
}
