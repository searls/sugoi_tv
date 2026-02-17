import SwiftUI

@MainActor
@Observable
public final class ChannelListViewModel {
  var channelGroups: [(category: String, channels: [ChannelDTO])] = []
  var isLoading: Bool = false
  var errorMessage: String?
  var searchText: String = ""

  private let channelService: ChannelService
  let config: ProductConfig
  private let defaults: UserDefaults
  private let cacheKey = "cachedChannels"

  public init(channelService: ChannelService, config: ProductConfig, defaults: UserDefaults = .standard) {
    self.channelService = channelService
    self.config = config
    self.defaults = defaults
  }

  /// Populate channelGroups from UserDefaults cache (synchronous, no network).
  func loadCachedChannels() {
    guard let data = defaults.data(forKey: cacheKey),
          let channels = try? JSONDecoder().decode([ChannelDTO].self, from: data),
          !channels.isEmpty else { return }
    channelGroups = ChannelService.groupByCategory(channels)
  }

  /// Persist the current flat channel list to UserDefaults after a successful fetch.
  private func cacheChannels(_ channels: [ChannelDTO]) async {
    let data = await Task.detached {
      try? JSONEncoder().encode(channels)
    }.value
    guard let data else { return }
    defaults.set(data, forKey: cacheKey)
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
      await cacheChannels(channels)
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
            ChannelRow(
              channel: channel,
              thumbnailURL: StreamURLBuilder.thumbnailURL(
                channelListHost: viewModel.config.channelListHost,
                playpath: channel.playpath
              )
            )
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
  let thumbnailURL: URL?

  @ViewBuilder
  private var thumbnail: some View {
    #if DEBUG
    if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1",
       let image = Self.bundleThumbnail(for: channel.id) {
      image.resizable().scaledToFill()
    } else {
      networkThumbnail
    }
    #else
    networkThumbnail
    #endif
  }

  private var networkThumbnail: some View {
    AsyncImage(url: thumbnailURL) { phase in
      switch phase {
      case .success(let image):
        image.resizable().scaledToFill()
      default:
        RoundedRectangle(cornerRadius: 6)
          .fill(.quaternary)
      }
    }
  }

  #if DEBUG
  private static func bundleThumbnail(for channelID: String) -> Image? {
    guard let url = Bundle.module.url(
      forResource: channelID, withExtension: "jpg",
      subdirectory: "PreviewContent/fixtures/thumbnails"
    ),
    let data = try? Data(contentsOf: url) else { return nil }
    #if os(macOS)
    guard let img = NSImage(data: data) else { return nil }
    return Image(nsImage: img)
    #else
    guard let img = UIImage(data: data) else { return nil }
    return Image(uiImage: img)
    #endif
  }
  #endif

  var body: some View {
    HStack(spacing: 12) {
      thumbnail
      .frame(width: 60, height: 34)
      .clipShape(RoundedRectangle(cornerRadius: 6))

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

// MARK: - Previews

private let previewChannelJSON = Data("""
{"id":"CH1","name":"NHK総合","description":"NHK General","tags":"$LIVE_CAT_関東","no":1,"playpath":"/query/s/abc","running":1}
""".utf8)

private let previewChannel = try! JSONDecoder().decode(ChannelDTO.self, from: previewChannelJSON)

#Preview("ChannelRow — with thumbnail") {
  ChannelRow(
    channel: previewChannel,
    thumbnailURL: StreamURLBuilder.thumbnailURL(
      channelListHost: "http://live.yoitv.com:9083",
      playpath: previewChannel.playpath
    )
  )
  .padding()
}

#Preview("ChannelRow — nil thumbnail") {
  ChannelRow(
    channel: previewChannel,
    thumbnailURL: nil
  )
  .padding()
}
