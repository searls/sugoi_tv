import SwiftData
import SwiftUI

struct ChannelListView: View {
  @Environment(AuthManager.self) private var authManager
  @Environment(ChannelStore.self) private var channelStore
  @Environment(\.modelContext) private var modelContext

  @State private var selectedChannel: Channel?

  var body: some View {
    NavigationSplitView {
      sidebar
        .navigationTitle("Channels")
    } detail: {
      if let channel = selectedChannel {
        EPGView(channel: channel)
          .id(channel.channelId)
      } else {
        ContentUnavailableView("Select a Channel", systemImage: "tv")
      }
    }
    .task {
      if let session = authManager.session {
        await channelStore.loadChannels(session: session, modelContext: modelContext)
      }
    }
  }

  @ViewBuilder
  private var sidebar: some View {
    if channelStore.isLoadingChannels && channelStore.channels.isEmpty {
      ProgressView("Loading channels...")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      List(selection: $selectedChannel) {
        ForEach(channelStore.categories, id: \.self) { category in
          Section(category) {
            ForEach(channelStore.channels(in: category)) { channel in
              ChannelRow(
                channel: channel,
                thumbnailHost: authManager.session?.productConfig.channelListHost ?? ""
              )
              .tag(channel)
            }
          }
        }
      }
      .refreshable {
        if let session = authManager.session {
          await channelStore.loadChannels(session: session, modelContext: modelContext)
        }
      }
    }
  }
}

// MARK: - Channel Row

struct ChannelRow: View {
  let channel: Channel
  let thumbnailHost: String

  var body: some View {
    HStack(spacing: 12) {
      AsyncImage(url: channel.thumbnailURL(host: thumbnailHost)) { image in
        image
          .resizable()
          .aspectRatio(16 / 9, contentMode: .fit)
      } placeholder: {
        RoundedRectangle(cornerRadius: 4)
          .fill(.quaternary)
          .aspectRatio(16 / 9, contentMode: .fit)
      }
      .frame(width: 80)
      .clipShape(RoundedRectangle(cornerRadius: 4))

      VStack(alignment: .leading, spacing: 2) {
        Text(channel.name)
          .font(.body)
          .lineLimit(1)

        if !channel.channelDescription.isEmpty {
          Text(channel.channelDescription)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }

      Spacer()

      if channel.isRunning {
        Circle()
          .fill(.green)
          .frame(width: 8, height: 8)
      }
    }
    .padding(.vertical, 2)
  }
}
