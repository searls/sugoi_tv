import Foundation

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

  public init(
    id: String,
    uid: String? = nil,
    name: String,
    description: String? = nil,
    tags: String? = nil,
    no: Int,
    timeshift: Int? = nil,
    timeshiftLen: Int? = nil,
    epgKeepDays: Int? = nil,
    state: Int? = nil,
    running: Int? = nil,
    playpath: String,
    liveType: String? = nil
  ) {
    self.id = id
    self.uid = uid
    self.name = name
    self.description = description
    self.tags = tags
    self.no = no
    self.timeshift = timeshift
    self.timeshiftLen = timeshiftLen
    self.epgKeepDays = epgKeepDays
    self.state = state
    self.running = running
    self.playpath = playpath
    self.liveType = liveType
  }

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

  /// Display name with common prefixes like "[HD]" stripped.
  public var displayName: String {
    name.replacingOccurrences(of: "[HD]", with: "")
      .trimmingCharacters(in: .whitespaces)
  }

  /// Display description with "[HD]" prefix stripped.
  /// Returns nil if it's a fuzzy match of the display name (redundant).
  public var displayDescription: String? {
    guard let raw = description?
      .replacingOccurrences(of: "[HD]", with: "")
      .trimmingCharacters(in: .whitespaces),
      !raw.isEmpty else { return nil }
    // Hide if it's just a case/whitespace variant of the display name
    let norm = { (s: String) in s.lowercased().filter { !$0.isWhitespace } }
    guard norm(raw) != norm(displayName) else { return nil }
    return raw
  }
}

// MARK: - Channel grouping

extension Array where Element == ChannelDTO {
  /// Group channels by their primary category in the given order.
  /// Categories not in `categoryOrder` are appended alphabetically.
  public func groupedByCategory(
    order categoryOrder: [String] = ["関東", "関西", "BS", "Others"]
  ) -> [(category: String, channels: [ChannelDTO])] {
    var groups: [String: [ChannelDTO]] = [:]
    for channel in self {
      let category = channel.primaryCategory
      groups[category, default: []].append(channel)
    }
    return categoryOrder.compactMap { category in
      guard let channels = groups[category] else { return nil }
      return (category: category, channels: channels)
    } + groups.filter { !categoryOrder.contains($0.key) }
      .sorted { $0.key < $1.key }
      .map { (category: $0.key, channels: $0.value) }
  }
}
