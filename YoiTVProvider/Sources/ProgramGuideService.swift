import Foundation
import SugoiCore
import SwiftData

/// Fetches and parses program guide data per channel
public actor ProgramGuideService {
  private let apiClient: any APIClientProtocol
  private let config: ProductConfig

  public init(apiClient: any APIClientProtocol, config: ProductConfig) {
    self.apiClient = apiClient
    self.config = config
  }

  /// Fetch program entries for a specific channel
  public func fetchPrograms(
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
    channelID: String,
    modelContext: ModelContext
  ) async throws -> [Program] {
    let dtos = try await fetchPrograms(channelID: channelID)

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
}

public enum ProgramGuideError: Error, Sendable {
  case fetchFailed(code: String)
  case channelNotFound(String)
}
