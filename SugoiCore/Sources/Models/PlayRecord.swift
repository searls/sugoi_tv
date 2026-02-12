import Foundation
import SwiftData

@Model
public final class PlayRecord {
  #Index<PlayRecord>([\.playedAt])

  public var vid: String = ""
  public var name: String = ""
  public var durationMs: Int = 0
  public var positionMs: Int = 0
  public var channelID: String = ""
  public var channelName: String = ""
  public var playedAt: Date = Date.distantPast

  public init() {}

  public init(from dto: PlayRecordDTO) {
    self.vid = dto.vid
    self.name = dto.name
    self.durationMs = dto.duration
    self.positionMs = dto.pos
    self.channelID = dto.channelId ?? ""
    self.channelName = dto.channelName ?? ""
    let timestamp = dto.playAt ?? dto.platAt ?? 0
    self.playedAt = Date(timeIntervalSince1970: TimeInterval(timestamp))
  }

  /// Playback progress as 0.0...1.0
  public var progress: Double {
    guard durationMs > 0 else { return 0 }
    return min(Double(positionMs) / Double(durationMs), 1.0)
  }

  /// Duration formatted as "HH:mm:ss" or "mm:ss"
  public var formattedDuration: String {
    Self.formatMilliseconds(durationMs)
  }

  /// Current position formatted
  public var formattedPosition: String {
    Self.formatMilliseconds(positionMs)
  }

  static func formatMilliseconds(_ ms: Int) -> String {
    let totalSeconds = ms / 1000
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60
    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%d:%02d", minutes, seconds)
  }
}
