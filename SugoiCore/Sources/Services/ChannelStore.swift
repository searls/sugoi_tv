import Foundation
import Observation
import SwiftData

@Observable @MainActor
final class ChannelStore {
  private(set) var channels: [Channel] = []
  private(set) var categories: [String] = []
  private(set) var epgEntries: [String: [EPGEntry]] = [:]  // channelId -> entries
  private(set) var isLoadingChannels = false
  private(set) var isLoadingEPG = false
  private(set) var errorMessage: String?

  private let api = APIClient.shared

  // MARK: - Load Channels

  func loadChannels(session: Session, modelContext: ModelContext) async {
    isLoadingChannels = true
    errorMessage = nil
    defer { isLoadingChannels = false }

    let config = session.productConfig
    do {
      let response = try await api.fetchChannels(
        host: config.channelListHost,
        cid: config.liveCid,
        uid: config.liveUid,
        referer: config.referer
      )

      guard let results = response.result else { return }

      // Upsert channels into SwiftData
      for result in results {
        let channelId = result.id
        let descriptor = FetchDescriptor<Channel>(
          predicate: #Predicate { $0.channelId == channelId }
        )
        if let existing = try modelContext.fetch(descriptor).first {
          existing.name = result.name
          existing.channelDescription = result.description ?? ""
          existing.tags = result.tags ?? ""
          existing.playpath = result.playpath ?? ""
          existing.sortOrder = result.no ?? 0
          existing.isRunning = (result.running ?? 0) == 1
          existing.supportsTimeshift = (result.timeshift ?? 0) == 1
          existing.epgKeepDays = result.epgKeepDays ?? 0
          existing.category = Channel.extractCategory(from: result.tags ?? "")
        } else {
          let channel = Channel(
            channelId: result.id,
            name: result.name,
            channelDescription: result.description ?? "",
            tags: result.tags ?? "",
            playpath: result.playpath ?? "",
            sortOrder: result.no ?? 0,
            isRunning: (result.running ?? 0) == 1,
            supportsTimeshift: (result.timeshift ?? 0) == 1,
            epgKeepDays: result.epgKeepDays ?? 0
          )
          modelContext.insert(channel)
        }
      }

      try modelContext.save()

      // Reload from SwiftData sorted by sortOrder
      let sorted = FetchDescriptor<Channel>(
        sortBy: [SortDescriptor(\.sortOrder)]
      )
      channels = try modelContext.fetch(sorted)

      // Extract unique categories preserving order
      var seen = Set<String>()
      categories = channels.compactMap { ch in
        if seen.contains(ch.category) { return nil }
        seen.insert(ch.category)
        return ch.category
      }

    } catch {
      errorMessage = error.localizedDescription
    }
  }

  // MARK: - Load EPG for a channel

  func loadEPG(for channel: Channel, session: Session) async {
    isLoadingEPG = true
    defer { isLoadingEPG = false }

    let config = session.productConfig
    do {
      let response = try await api.fetchEPG(
        host: config.channelListHost,
        cid: config.liveCid,
        uid: config.liveUid,
        channelId: channel.channelId,
        referer: config.referer,
        days: config.epgDays ?? 30
      )

      if let first = response.result?.first,
        let epgJson = first.recordEpg
      {
        epgEntries[channel.channelId] = EPGEntry.parse(
          json: epgJson, channelId: channel.channelId)
      } else {
        epgEntries[channel.channelId] = []
      }
    } catch {
      errorMessage = error.localizedDescription
      epgEntries[channel.channelId] = []
    }
  }

  func channels(in category: String) -> [Channel] {
    channels.filter { $0.category == category }
  }
}
