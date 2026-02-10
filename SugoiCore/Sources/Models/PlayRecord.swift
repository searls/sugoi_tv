import Foundation
import SwiftData

@Model
final class PlayRecord {
  @Attribute(.unique) var vid: String
  var name: String
  var durationMs: Int
  var positionMs: Int
  var channelId: String
  var channelName: String
  var playedAt: Date

  init(
    vid: String,
    name: String,
    durationMs: Int = 0,
    positionMs: Int = 0,
    channelId: String = "",
    channelName: String = "",
    playedAt: Date = .now
  ) {
    self.vid = vid
    self.name = name
    self.durationMs = durationMs
    self.positionMs = positionMs
    self.channelId = channelId
    self.channelName = channelName
    self.playedAt = playedAt
  }
}
