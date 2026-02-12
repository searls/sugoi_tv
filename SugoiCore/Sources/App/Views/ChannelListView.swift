import SwiftUI

@MainActor
@Observable
public final class ChannelListViewModel {
  var channelGroups: [(category: String, channels: [ChannelDTO])] = []
  var isLoading: Bool = false
  var errorMessage: String?
  var searchText: String = ""

  private let channelService: ChannelService
  private let config: ProductConfig

  public init(channelService: ChannelService, config: ProductConfig) {
    self.channelService = channelService
    self.config = config
  }

  var filteredGroups: [(category: String, channels: [ChannelDTO])] {
    guard !searchText.isEmpty else { return channelGroups }
    return channelGroups.compactMap { group in
      let filtered = group.channels.filter {
        $0.name.localizedCaseInsensitiveContains(searchText)
          || ($0.description?.localizedCaseInsensitiveContains(searchText) ?? false)
      }
      guard !filtered.isEmpty else { return nil }
      return (category: group.category, channels: filtered)
    }
  }

  func loadChannels() async {
    isLoading = true
    errorMessage = nil
    do {
      let channels = try await channelService.fetchChannels(config: config)
      channelGroups = ChannelService.groupByCategory(channels)
    } catch {
      errorMessage = "Failed to load channels."
    }
    isLoading = false
  }
}

public struct ChannelListView: View {
  @Bindable var viewModel: ChannelListViewModel
  var onSelectChannel: (ChannelDTO) -> Void

  public init(viewModel: ChannelListViewModel, onSelectChannel: @escaping (ChannelDTO) -> Void) {
    self.viewModel = viewModel
    self.onSelectChannel = onSelectChannel
  }

  public var body: some View {
    Group {
      if viewModel.isLoading && viewModel.channelGroups.isEmpty {
        ProgressView("Loading channels...")
      } else if let error = viewModel.errorMessage, viewModel.channelGroups.isEmpty {
        ContentUnavailableView {
          Label("Error", systemImage: "exclamationmark.triangle")
        } description: {
          Text(error)
        } actions: {
          Button("Retry") { Task { await viewModel.loadChannels() } }
        }
      } else {
        channelList
      }
    }
  }

  private var channelList: some View {
    List {
      ForEach(viewModel.filteredGroups, id: \.category) { group in
        Section(group.category) {
          ForEach(group.channels, id: \.id) { channel in
            ChannelRow(channel: channel, channelListHost: "")
              .contentShape(Rectangle())
              .onTapGesture { onSelectChannel(channel) }
          }
        }
      }
    }
    .listStyle(.plain)
  }
}

struct ChannelRow: View {
  let channel: ChannelDTO
  let channelListHost: String

  var body: some View {
    HStack(spacing: 12) {
      // Thumbnail placeholder
      RoundedRectangle(cornerRadius: 6)
        .fill(.quaternary)
        .frame(width: 60, height: 34)
        .overlay {
          if channel.running == 1 {
            Circle()
              .fill(.red)
              .frame(width: 8, height: 8)
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
              .padding(4)
          }
        }

      VStack(alignment: .leading, spacing: 2) {
        Text(channel.name)
          .font(.body)
          .lineLimit(1)

        if let desc = channel.description, !desc.isEmpty {
          Text(desc)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }

      Spacer()
    }
    .padding(.vertical, 2)
  }
}
