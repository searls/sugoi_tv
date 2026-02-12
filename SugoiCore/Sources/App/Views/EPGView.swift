import SwiftUI

@MainActor
@Observable
public final class EPGViewModel {
  var entries: [EPGEntryDTO] = []
  var isLoading: Bool = false
  var errorMessage: String?
  var channelName: String = ""

  private let epgService: EPGService
  private let config: ProductConfig
  private let channelID: String

  public init(epgService: EPGService, config: ProductConfig, channelID: String, channelName: String) {
    self.epgService = epgService
    self.config = config
    self.channelID = channelID
    self.channelName = channelName
  }

  var currentProgram: EPGEntryDTO? {
    EPGService.currentProgram(in: entries)
  }

  func loadEPG() async {
    isLoading = true
    errorMessage = nil
    do {
      entries = try await epgService.fetchEPG(config: config, channelID: channelID)
    } catch {
      errorMessage = "Failed to load program guide."
    }
    isLoading = false
  }
}

public struct EPGView: View {
  @Bindable var viewModel: EPGViewModel
  var onPlayLive: () -> Void
  var onPlayVOD: (EPGEntryDTO) -> Void

  public init(
    viewModel: EPGViewModel,
    onPlayLive: @escaping () -> Void,
    onPlayVOD: @escaping (EPGEntryDTO) -> Void
  ) {
    self.viewModel = viewModel
    self.onPlayLive = onPlayLive
    self.onPlayVOD = onPlayVOD
  }

  public var body: some View {
    Group {
      if viewModel.isLoading && viewModel.entries.isEmpty {
        ProgressView("Loading guide...")
      } else if let error = viewModel.errorMessage, viewModel.entries.isEmpty {
        ContentUnavailableView {
          Label("Error", systemImage: "exclamationmark.triangle")
        } description: {
          Text(error)
        } actions: {
          Button("Retry") { Task { await viewModel.loadEPG() } }
        }
      } else {
        epgList
      }
    }
    .task { await viewModel.loadEPG() }
    .navigationTitle(viewModel.channelName)
  }

  private var epgList: some View {
    List {
      // Live now section
      if let current = viewModel.currentProgram {
        Section("Now Playing") {
          EPGRow(entry: current, isCurrent: true)
            .onTapGesture { onPlayLive() }
        }
      }

      // Full schedule
      Section("Schedule") {
        ForEach(viewModel.entries, id: \.time) { entry in
          EPGRow(
            entry: entry,
            isCurrent: entry == viewModel.currentProgram
          )
          .onTapGesture {
            if entry.hasVOD {
              onPlayVOD(entry)
            } else if entry == viewModel.currentProgram {
              onPlayLive()
            }
          }
        }
      }
    }
  }
}

struct EPGRow: View {
  let entry: EPGEntryDTO
  let isCurrent: Bool

  private static let jstFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    f.timeZone = TimeZone(identifier: "Asia/Tokyo")
    return f
  }()

  var body: some View {
    HStack(spacing: 12) {
      // Time
      Text(Self.jstFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(entry.time))))
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(width: 44, alignment: .leading)

      // Title
      VStack(alignment: .leading, spacing: 2) {
        Text(entry.title)
          .font(isCurrent ? .body.bold() : .body)
          .lineLimit(2)
      }

      Spacer()

      // Status badges
      if isCurrent {
        Text("LIVE")
          .font(.caption2.bold())
          .foregroundStyle(.white)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(.red, in: Capsule())
      } else if entry.hasVOD {
        Image(systemName: "play.circle")
          .foregroundStyle(.blue)
      }
    }
    .padding(.vertical, 2)
    .contentShape(Rectangle())
  }
}
