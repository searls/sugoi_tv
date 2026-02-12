import Foundation
import SwiftData

/// Fetches and parses EPG (Electronic Program Guide) data per channel
public actor EPGService {
  private let apiClient: any APIClientProtocol

  public init(apiClient: any APIClientProtocol) {
    self.apiClient = apiClient
  }

  /// Fetch EPG entries for a specific channel
  public func fetchEPG(
    config: ProductConfig,
    channelID: String
  ) async throws -> [EPGEntryDTO] {
    let url = YoiTVEndpoints.epgURL(config: config, channelID: channelID)
    let response: EPGChannelResponse = try await apiClient.get(url: url)
    guard response.code == "OK" else {
      throw EPGServiceError.fetchFailed(code: response.code)
    }
    guard let channelData = response.result.first else {
      throw EPGServiceError.channelNotFound(channelID)
    }
    return try channelData.parseEPGEntries()
  }

  /// Fetch EPG and sync to SwiftData
  @MainActor
  public func syncEPG(
    config: ProductConfig,
    channelID: String,
    modelContext: ModelContext
  ) async throws -> [EPGEntry] {
    let dtos = try await fetchEPG(config: config, channelID: channelID)

    // Delete existing EPG entries for this channel
    let descriptor = FetchDescriptor<EPGEntry>(
      predicate: #Predicate { $0.channelID == channelID }
    )
    let existing = try modelContext.fetch(descriptor)
    for entry in existing {
      modelContext.delete(entry)
    }

    // Insert fresh entries
    var result: [EPGEntry] = []
    for dto in dtos {
      let entry = EPGEntry(from: dto, channelID: channelID)
      modelContext.insert(entry)
      result.append(entry)
    }

    try modelContext.save()
    return result.sorted { $0.startTime < $1.startTime }
  }

  /// Find the currently-airing program from a list of EPG entries
  public static func currentProgram(
    in entries: [EPGEntryDTO],
    at date: Date = Date()
  ) -> EPGEntryDTO? {
    let timestamp = Int(date.timeIntervalSince1970)
    // Find the last entry whose start time is <= now
    return entries.last { $0.time <= timestamp }
  }

  /// Find upcoming programs (starting after now)
  public static func upcomingPrograms(
    in entries: [EPGEntryDTO],
    after date: Date = Date(),
    limit: Int = 10
  ) -> [EPGEntryDTO] {
    let timestamp = Int(date.timeIntervalSince1970)
    return Array(entries.filter { $0.time > timestamp }.prefix(limit))
  }

  /// Find past programs with VOD available
  public static func vodAvailable(
    in entries: [EPGEntryDTO],
    before date: Date = Date()
  ) -> [EPGEntryDTO] {
    let timestamp = Int(date.timeIntervalSince1970)
    return entries.filter { $0.time < timestamp && $0.hasVOD }
  }
}

public enum EPGServiceError: Error, Sendable {
  case fetchFailed(code: String)
  case channelNotFound(String)
}
