import Foundation

public struct PlayRecordListResponse: Codable, Sendable {
  public let data: [PlayRecordDTO]?
  public let code: String
}

public struct PlayRecordDTO: Codable, Sendable, Equatable {
  public let vid: String
  public let name: String
  public let duration: Int      // Total duration in milliseconds
  public let pos: Int           // Current playback position in milliseconds
  public let playAt: Int?       // Last played timestamp (Unix seconds)
  public let platAt: Int?       // Alternate field name (API inconsistency)
  public let channelId: String?
  public let channelName: String?

  /// Playback progress as 0.0...1.0
  public var progress: Double {
    guard duration > 0 else { return 0 }
    return min(Double(pos) / Double(duration), 1.0)
  }
}

public struct PlayRecordSyncRequest: Codable, Sendable {
  public let updates: [PlayRecordSyncEntry]

  public init(updates: [PlayRecordSyncEntry]) {
    self.updates = updates
  }
}

public struct PlayRecordSyncEntry: Codable, Sendable {
  public let vid: String
  public let name: String
  public let duration: Int
  public let pos: Int
  public let ended: Bool
  public let channelId: String
  public let channelName: String

  public init(
    vid: String, name: String, duration: Int, pos: Int,
    ended: Bool, channelId: String, channelName: String
  ) {
    self.vid = vid
    self.name = name
    self.duration = duration
    self.pos = pos
    self.ended = ended
    self.channelId = channelId
    self.channelName = channelName
  }
}
