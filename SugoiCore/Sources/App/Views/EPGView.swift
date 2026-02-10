import SwiftUI

struct EPGView: View {
  let channel: Channel

  @Environment(AuthManager.self) private var authManager
  @Environment(ChannelStore.self) private var channelStore

  @State private var selectedEntry: EPGEntry?
  @State private var showPlayer = false

  private static let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.timeZone = TimeZone(identifier: "Asia/Tokyo")
    f.dateFormat = "HH:mm"
    return f
  }()

  private static let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.timeZone = TimeZone(identifier: "Asia/Tokyo")
    f.dateFormat = "M/d (EEE)"
    f.locale = Locale(identifier: "ja_JP")
    return f
  }()

  var body: some View {
    VStack(spacing: 0) {
      // Live playback header
      liveHeader

      // EPG list
      epgList
    }
    .navigationTitle(channel.name)
    .task {
      if let session = authManager.session {
        await channelStore.loadEPG(for: channel, session: session)
      }
    }
    #if os(macOS)
      .sheet(isPresented: $showPlayer) {
        if let session = authManager.session {
          PlayerView(
            session: session,
            channel: channel,
            vodEntry: selectedEntry
          )
          .frame(minWidth: 640, minHeight: 360)
        }
      }
    #else
      .fullScreenCover(isPresented: $showPlayer) {
        if let session = authManager.session {
          PlayerView(
            session: session,
            channel: channel,
            vodEntry: selectedEntry
          )
        }
      }
    #endif
  }

  @ViewBuilder
  private var liveHeader: some View {
    if channel.isRunning {
      Button {
        selectedEntry = nil
        showPlayer = true
      } label: {
        HStack {
          Image(systemName: "play.circle.fill")
            .font(.title2)
          VStack(alignment: .leading) {
            Text("Watch Live")
              .font(.headline)
            if let nowPlaying = currentProgram {
              Text(nowPlaying.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
          Spacer()
          Image(systemName: "chevron.right")
            .foregroundStyle(.secondary)
        }
        .padding()
      }
      .buttonStyle(.plain)

      Divider()
    }
  }

  @ViewBuilder
  private var epgList: some View {
    let entries = channelStore.epgEntries[channel.channelId] ?? []

    if channelStore.isLoadingEPG && entries.isEmpty {
      ProgressView("Loading program guide...")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if entries.isEmpty {
      ContentUnavailableView("No Programs", systemImage: "list.bullet")
    } else {
      let grouped = groupedByDate(entries)
      List {
        ForEach(grouped, id: \.date) { group in
          Section(Self.dateFormatter.string(from: group.date)) {
            ForEach(group.entries) { entry in
              EPGRow(entry: entry, isCurrent: isCurrentProgram(entry))
                .onTapGesture {
                  if entry.hasVOD {
                    selectedEntry = entry
                    showPlayer = true
                  }
                }
            }
          }
        }
      }
    }
  }

  private var currentProgram: EPGEntry? {
    let entries = channelStore.epgEntries[channel.channelId] ?? []
    let now = Date()
    return entries.last { $0.startTime <= now }
  }

  private func isCurrentProgram(_ entry: EPGEntry) -> Bool {
    guard let current = currentProgram else { return false }
    return current.id == entry.id
  }

  private struct DateGroup {
    let date: Date
    let entries: [EPGEntry]
  }

  private func groupedByDate(_ entries: [EPGEntry]) -> [DateGroup] {
    let calendar = Calendar(identifier: .gregorian)
    var cal = calendar
    cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!

    let grouped = Dictionary(grouping: entries) { entry in
      cal.startOfDay(for: entry.startTime)
    }

    return grouped.sorted { $0.key > $1.key }
      .map { DateGroup(date: $0.key, entries: $0.value.sorted { $0.startTime < $1.startTime }) }
  }
}

// MARK: - EPG Row

struct EPGRow: View {
  let entry: EPGEntry
  let isCurrent: Bool

  private static let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.timeZone = TimeZone(identifier: "Asia/Tokyo")
    f.dateFormat = "HH:mm"
    return f
  }()

  var body: some View {
    HStack(spacing: 12) {
      Text(Self.timeFormatter.string(from: entry.startTime))
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(width: 44, alignment: .trailing)

      VStack(alignment: .leading, spacing: 2) {
        Text(entry.title)
          .font(.body)
          .lineLimit(2)
          .fontWeight(isCurrent ? .semibold : .regular)
      }

      Spacer()

      if entry.hasVOD {
        Image(systemName: "play.rectangle")
          .foregroundStyle(.secondary)
          .font(.caption)
      }

      if isCurrent {
        Text("ON AIR")
          .font(.caption2.bold())
          .foregroundStyle(.white)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(.red, in: Capsule())
      }
    }
    .padding(.vertical, 2)
    .contentShape(Rectangle())
  }
}
