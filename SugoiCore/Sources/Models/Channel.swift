import Foundation
import SwiftData

@Model
public final class Channel {
  #Index<Channel>([\.no])

  public var channelID: String = ""
  public var name: String = ""
  public var channelDescription: String = ""
  public var tags: String = ""
  public var playpath: String = ""
  public var no: Int = 0
  public var isRunning: Bool = false
  public var supportsTimeshift: Bool = false
  public var timeshiftLen: Int = 0
  public var epgKeepDays: Int = 0
  public var state: Int = 0
  public var liveType: String = "video"
  public var lastUpdated: Date = Date.distantPast

  public init() {}

  public init(from dto: ChannelDTO) {
    self.channelID = dto.id
    self.name = dto.name
    self.channelDescription = dto.description ?? ""
    self.tags = dto.tags ?? ""
    self.playpath = dto.playpath
    self.no = dto.no
    self.isRunning = (dto.running ?? 0) == 1
    self.supportsTimeshift = (dto.timeshift ?? 0) == 1
    self.timeshiftLen = dto.timeshiftLen ?? 0
    self.epgKeepDays = dto.epgKeepDays ?? 0
    self.state = dto.state ?? 0
    self.liveType = dto.liveType ?? "video"
    self.lastUpdated = Date()
  }

  /// Update from a fresh API response
  public func update(from dto: ChannelDTO) {
    self.name = dto.name
    self.channelDescription = dto.description ?? ""
    self.tags = dto.tags ?? ""
    self.playpath = dto.playpath
    self.no = dto.no
    self.isRunning = (dto.running ?? 0) == 1
    self.supportsTimeshift = (dto.timeshift ?? 0) == 1
    self.timeshiftLen = dto.timeshiftLen ?? 0
    self.epgKeepDays = dto.epgKeepDays ?? 0
    self.state = dto.state ?? 0
    self.liveType = dto.liveType ?? "video"
    self.lastUpdated = Date()
  }

  /// Categories extracted from `$LIVE_CAT_` prefixed tags
  public var categories: [String] {
    guard !tags.isEmpty else { return [] }
    return tags.split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { $0.hasPrefix("$LIVE_CAT_") }
      .map { String($0.dropFirst("$LIVE_CAT_".count)) }
  }

  public var primaryCategory: String {
    categories.first ?? "Others"
  }

  /// Thumbnail URL given a VMS host base
  public func thumbnailURL(host: String) -> URL? {
    URL(string: "\(host)\(playpath).jpg?type=live&thumbnail=thumbnail_small.jpg")
  }
}
