import SwiftUI

// MARK: - Card

struct ChannelCardView: View {
  let channel: ChannelDTO
  let thumbnailURL: URL?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      thumbnail
        .aspectRatio(11.0 / 8.0, contentMode: .fill)
        .clipped()

      Text(channel.displayName)
        .font(.caption)
        .fontWeight(.medium)
        .lineLimit(1)
        .truncationMode(.tail)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(.background.shadow(.drop(color: .black.opacity(0.15), radius: 4, y: 2)))
    )
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(.quaternary, lineWidth: 0.5)
    )
    .accessibilityLabel(channel.displayName)
  }

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
        fallbackView
      }
    }
  }

  private var fallbackView: some View {
    Color.clear
      .aspectRatio(11.0 / 8.0, contentMode: .fill)
      .overlay {
        Text(channel.displayName)
          .font(.caption2)
          .multilineTextAlignment(.center)
          .foregroundStyle(.secondary)
          .padding(4)
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
}

// MARK: - Grid

struct ChannelGridView: View {
  let channelGroups: [(category: String, channels: [ChannelDTO])]
  let channelListHost: String
  var onSelectChannel: (ChannelDTO) -> Void

  var body: some View {
    ScrollView {
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 140), spacing: 16)],
        spacing: 20
      ) {
        ForEach(channelGroups, id: \.category) { group in
          Section {
            ForEach(group.channels) { channel in
              Button {
                onSelectChannel(channel)
              } label: {
                ChannelCardView(
                  channel: channel,
                  thumbnailURL: StreamURLBuilder.thumbnailURL(
                    channelListHost: channelListHost,
                    playpath: channel.playpath
                  )
                )
              }
              .buttonStyle(.plain)
              .id(channel.id)
            }
          } header: {
            Text(group.category)
              .font(.headline)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.top, 8)
          }
        }
      }
      .padding(.horizontal)
    }
  }
}

// MARK: - Previews

#Preview("ChannelGridView") {
  let data = try! Data(
    contentsOf: Bundle.module.url(
      forResource: "channels", withExtension: "json",
      subdirectory: "PreviewContent/fixtures"
    )!
  )
  let response = try! JSONDecoder().decode(ChannelListResponse.self, from: data)
  let groups = ChannelService.groupByCategory(response.result)

  NavigationStack {
    ChannelGridView(
      channelGroups: groups,
      channelListHost: "http://live.yoitv.com:9083",
      onSelectChannel: { _ in }
    )
    .navigationTitle("Channels")
  }
}
