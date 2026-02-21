import Foundation

/// A single program entry
public struct ProgramDTO: Codable, Sendable, Equatable, Identifiable {
  public let time: Int     // Unix seconds
  public let title: String
  public let path: String  // Empty string = live-only (no VOD recording)

  /// VOD programs use path as ID; live-only programs fall back to time.
  public var id: String { path.isEmpty ? "live-\(time)" : path }

  /// Whether this program has a catch-up VOD recording
  public var hasVOD: Bool { !path.isEmpty }
}

// MARK: - Program list queries

extension Array where Element == ProgramDTO {
  /// Find the currently-airing program from a sorted list of program entries.
  public func liveProgram(at date: Date = Date()) -> ProgramDTO? {
    let timestamp = Int(date.timeIntervalSince1970)
    return last { $0.time <= timestamp }
  }

  /// Find upcoming programs (starting after now).
  public func upcomingPrograms(after date: Date = Date(), limit: Int = 10) -> [ProgramDTO] {
    let timestamp = Int(date.timeIntervalSince1970)
    return Array(filter { $0.time > timestamp }.prefix(limit))
  }

  /// Find past programs with VOD available.
  public func vodAvailable(before date: Date = Date()) -> [ProgramDTO] {
    let timestamp = Int(date.timeIntervalSince1970)
    return filter { $0.time < timestamp && $0.hasVOD }
  }
}
