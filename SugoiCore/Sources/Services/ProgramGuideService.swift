import Foundation
import SwiftData

/// Fetches and parses program guide data per channel
public actor ProgramGuideService {
  private let apiClient: any APIClientProtocol

  public init(apiClient: any APIClientProtocol) {
    self.apiClient = apiClient
  }

  /// Fetch program entries for a specific channel
  public func fetchPrograms(
    config: ProductConfig,
    channelID: String
  ) async throws -> [ProgramDTO] {
    let url = YoiTVEndpoints.epgURL(config: config, channelID: channelID)
    let response: ChannelProgramsResponse = try await apiClient.get(url: url)
    guard response.code == "OK" else {
      throw ProgramGuideError.fetchFailed(code: response.code)
    }
    guard let channelData = response.result.first else {
      throw ProgramGuideError.channelNotFound(channelID)
    }
    return try channelData.parsePrograms()
  }

  /// Fetch programs and sync to SwiftData
  @MainActor
  public func syncPrograms(
    config: ProductConfig,
    channelID: String,
    modelContext: ModelContext
  ) async throws -> [Program] {
    let dtos = try await fetchPrograms(config: config, channelID: channelID)

    // Delete existing program entries for this channel
    let descriptor = FetchDescriptor<Program>(
      predicate: #Predicate { $0.channelID == channelID }
    )
    let existing = try modelContext.fetch(descriptor)
    for entry in existing {
      modelContext.delete(entry)
    }

    // Insert fresh entries
    var result: [Program] = []
    for dto in dtos {
      let entry = Program(from: dto, channelID: channelID)
      modelContext.insert(entry)
      result.append(entry)
    }

    try modelContext.save()
    return result.sorted { $0.startTime < $1.startTime }
  }

  /// Find the currently-airing program from a list of program entries
  public static func liveProgram(
    in entries: [ProgramDTO],
    at date: Date = Date()
  ) -> ProgramDTO? {
    let timestamp = Int(date.timeIntervalSince1970)
    // Find the last entry whose start time is <= now
    return entries.last { $0.time <= timestamp }
  }

  /// Find upcoming programs (starting after now)
  public static func upcomingPrograms(
    in entries: [ProgramDTO],
    after date: Date = Date(),
    limit: Int = 10
  ) -> [ProgramDTO] {
    let timestamp = Int(date.timeIntervalSince1970)
    return Array(entries.filter { $0.time > timestamp }.prefix(limit))
  }

  /// Find past programs with VOD available
  public static func vodAvailable(
    in entries: [ProgramDTO],
    before date: Date = Date()
  ) -> [ProgramDTO] {
    let timestamp = Int(date.timeIntervalSince1970)
    return entries.filter { $0.time < timestamp && $0.hasVOD }
  }
}

public enum ProgramGuideError: Error, Sendable {
  case fetchFailed(code: String)
  case channelNotFound(String)
}
