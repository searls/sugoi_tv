import Foundation
import SugoiCore

/// Response from `listLives` with `no_epg=0` and `vid={channelId}`
public struct ChannelProgramsResponse: Codable, Sendable {
  public let result: [ChannelProgramsDTO]
  public let code: String
}

/// Channel object that includes program history via double-encoded `record_epg`
public struct ChannelProgramsDTO: Codable, Sendable {
  public let id: String
  public let name: String
  public let programHistory: String?

  enum CodingKeys: String, CodingKey {
    case id, name
    case programHistory = "record_epg"
  }

  /// Parse the double-encoded program entries from `record_epg`
  public func parsePrograms() throws -> [ProgramDTO] {
    guard let json = programHistory, !json.isEmpty else { return [] }
    guard let data = json.data(using: .utf8) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: [], debugDescription: "record_epg is not valid UTF-8")
      )
    }
    return try JSONDecoder().decode([ProgramDTO].self, from: data)
  }
}
