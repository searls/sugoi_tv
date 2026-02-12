import Foundation

/// Response from `listLives` with `no_epg=0` and `vid={channelId}`
public struct EPGChannelResponse: Codable, Sendable {
  public let result: [EPGChannelDTO]
  public let code: String
}

/// Channel object that includes EPG data via double-encoded `record_epg`
public struct EPGChannelDTO: Codable, Sendable {
  public let id: String
  public let name: String
  public let recordEpg: String?

  enum CodingKeys: String, CodingKey {
    case id, name
    case recordEpg = "record_epg"
  }

  /// Parse the double-encoded EPG entries from `record_epg`
  public func parseEPGEntries() throws -> [EPGEntryDTO] {
    guard let json = recordEpg, !json.isEmpty else { return [] }
    guard let data = json.data(using: .utf8) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: [], debugDescription: "record_epg is not valid UTF-8")
      )
    }
    return try JSONDecoder().decode([EPGEntryDTO].self, from: data)
  }
}

/// A single EPG program entry
public struct EPGEntryDTO: Codable, Sendable, Equatable {
  public let time: Int     // Unix seconds
  public let title: String
  public let path: String  // Empty string = live-only (no VOD recording)

  /// Whether this program has a catch-up VOD recording
  public var hasVOD: Bool { !path.isEmpty }
}
