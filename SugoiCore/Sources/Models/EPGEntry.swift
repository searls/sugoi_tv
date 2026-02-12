import Foundation
import SwiftData

@Model
public final class EPGEntry {
  #Index<EPGEntry>([\.startTime])

  public var channelID: String = ""
  public var title: String = ""
  public var path: String = ""
  public var startTime: Date = Date.distantPast

  public init() {}

  public init(from dto: EPGEntryDTO, channelID: String) {
    self.channelID = channelID
    self.title = dto.title
    self.path = dto.path
    self.startTime = Date(timeIntervalSince1970: TimeInterval(dto.time))
  }

  /// Whether this program has a catch-up VOD recording
  public var hasVOD: Bool { !path.isEmpty }

  /// Format the start time for display in JST (Asia/Tokyo)
  public var formattedStartTime: String {
    EPGEntry.jstFormatter.string(from: startTime)
  }

  /// Format as short time only (e.g. "14:30")
  public var formattedTime: String {
    EPGEntry.jstTimeFormatter.string(from: startTime)
  }

  private static let jstFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    f.timeZone = TimeZone(identifier: "Asia/Tokyo")
    f.locale = Locale(identifier: "ja_JP")
    return f
  }()

  private static let jstTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    f.timeZone = TimeZone(identifier: "Asia/Tokyo")
    return f
  }()
}
