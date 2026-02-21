import Foundation
import SugoiCore
import SwiftData

/// Fetches and caches the channel list from the VMS API
public actor ChannelService {
  private let apiClient: any APIClientProtocol
  private let config: ProductConfig
  /// Exposed for thumbnail URL construction without crossing actor boundary.
  public nonisolated let channelListHost: String

  public init(apiClient: any APIClientProtocol, config: ProductConfig) {
    self.apiClient = apiClient
    self.config = config
    self.channelListHost = config.channelListHost
  }

  /// Fetch all channels from the API
  public func fetchChannels() async throws -> [ChannelDTO] {
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
    modelContext: ModelContext
  ) async throws -> [Channel] {
    let dtos = try await fetchChannels()

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

  /// Thumbnail URL for a channel (no auth required)
  public nonisolated func thumbnailURL(for channel: ChannelDTO) -> URL? {
    StreamURLBuilder.thumbnailURL(
      channelListHost: channelListHost,
      playpath: channel.playpath
    )
  }

}

public enum ChannelServiceError: Error, Sendable {
  case fetchFailed(code: String)
}
