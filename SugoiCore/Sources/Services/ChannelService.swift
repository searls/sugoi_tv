import Foundation
import SwiftData

/// Fetches and caches the channel list from the VMS API
public actor ChannelService {
  private let apiClient: any APIClientProtocol

  public init(apiClient: any APIClientProtocol) {
    self.apiClient = apiClient
  }

  /// Fetch all channels from the API
  public func fetchChannels(config: ProductConfig) async throws -> [ChannelDTO] {
    let url = YoiTVEndpoints.channelListURL(config: config)
    let response: ChannelListResponse = try await apiClient.get(url: url)
    guard response.code == "OK" else {
      throw ChannelServiceError.fetchFailed(code: response.code)
    }
    return response.result
  }

  /// Fetch channels and upsert into SwiftData
  @MainActor
  public func syncChannels(
    config: ProductConfig,
    modelContext: ModelContext
  ) async throws -> [Channel] {
    let dtos = try await fetchChannels(config: config)

    // Fetch existing channels for upsert
    let descriptor = FetchDescriptor<Channel>()
    let existing = try modelContext.fetch(descriptor)
    let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.channelID, $0) })

    var result: [Channel] = []
    for dto in dtos {
      if let channel = existingByID[dto.id] {
        channel.update(from: dto)
        result.append(channel)
      } else {
        let channel = Channel(from: dto)
        modelContext.insert(channel)
        result.append(channel)
      }
    }

    try modelContext.save()
    return result.sorted { $0.no < $1.no }
  }

  /// Group channels by their primary category
  public static func groupByCategory(_ channels: [ChannelDTO]) -> [(category: String, channels: [ChannelDTO])] {
    var groups: [String: [ChannelDTO]] = [:]
    for channel in channels {
      let category = channel.primaryCategory
      groups[category, default: []].append(channel)
    }

    // Sort categories in a stable order
    let categoryOrder = ["関東", "関西", "BS", "Others"]
    return categoryOrder.compactMap { category in
      guard let channels = groups[category] else { return nil }
      return (category: category, channels: channels)
    } + groups.filter { !categoryOrder.contains($0.key) }
      .sorted { $0.key < $1.key }
      .map { (category: $0.key, channels: $0.value) }
  }
}

public enum ChannelServiceError: Error, Sendable {
  case fetchFailed(code: String)
}
