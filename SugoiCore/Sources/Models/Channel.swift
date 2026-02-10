import Foundation
import SwiftData

@Model
final class Channel {
  @Attribute(.unique) var channelId: String
  var name: String
  var channelDescription: String
  var tags: String
  var playpath: String
  var sortOrder: Int
  var isRunning: Bool
  var supportsTimeshift: Bool
  var epgKeepDays: Int
  var category: String

  init(
    channelId: String,
    name: String,
    channelDescription: String = "",
    tags: String = "",
    playpath: String = "",
    sortOrder: Int = 0,
    isRunning: Bool = false,
    supportsTimeshift: Bool = false,
    epgKeepDays: Int = 0
  ) {
    self.channelId = channelId
    self.name = name
    self.channelDescription = channelDescription
    self.tags = tags
    self.playpath = playpath
    self.sortOrder = sortOrder
    self.isRunning = isRunning
    self.supportsTimeshift = supportsTimeshift
    self.epgKeepDays = epgKeepDays
    self.category = Channel.extractCategory(from: tags)
  }

  static func extractCategory(from tags: String) -> String {
    let parts = tags.split(separator: ",").map {
      $0.trimmingCharacters(in: .whitespaces)
    }
    if let catTag = parts.first(where: { $0.hasPrefix("$LIVE_CAT_") }) {
      return String(catTag.dropFirst("$LIVE_CAT_".count))
    }
    return "Others"
  }

  func thumbnailURL(host: String) -> URL? {
    URL(string: "\(host)\(playpath).jpg?type=live&thumbnail=thumbnail_small.jpg")
  }
}
