import SwiftUI

// MARK: - Date section for past programs grouped by JST calendar day

public struct DateSection: Sendable, Equatable {
  public let label: String
  public let programs: [ProgramDTO]
}

// MARK: - ViewModel

@MainActor
@Observable
public final class ProgramListViewModel {
  var entries: [ProgramDTO] = []
  var isLoading: Bool = false
  var errorMessage: String?
  var channelName: String = ""

  private let programGuideService: ProgramGuideService
  private let config: ProductConfig
  let channelID: String

  public init(programGuideService: ProgramGuideService, config: ProductConfig, channelID: String, channelName: String) {
    self.programGuideService = programGuideService
    self.config = config
    self.channelID = channelID
    self.channelName = channelName
  }

  var currentProgram: ProgramDTO? {
    ProgramGuideService.currentProgram(in: entries)
  }

  var upcomingPrograms: [ProgramDTO] {
    ProgramGuideService.upcomingPrograms(in: entries, limit: 5)
  }

  var pastByDate: [DateSection] {
    Self.groupPastByDate(entries: entries, current: currentProgram)
  }

  #if DEBUG
  /// Preview-only factory that creates a ViewModel with pre-loaded entries (no service needed).
  static func __preview_create(channelName: String, entries: [ProgramDTO]) -> ProgramListViewModel {
    let vm = ProgramListViewModel(
      programGuideService: ProgramGuideService(apiClient: _NoOpAPIClient()),
      config: try! JSONDecoder().decode(ProductConfig.self, from: Data(#"{"vms_host":"x","vms_uid":"x","vms_live_cid":"x","vms_referer":"x"}"#.utf8)),
      channelID: "preview",
      channelName: channelName
    )
    vm.entries = entries
    return vm
  }
  #endif

  func loadPrograms() async {
    guard entries.isEmpty else { return }
    isLoading = true
    errorMessage = nil
    do {
      entries = try await programGuideService.fetchPrograms(config: config, channelID: channelID)
    } catch {
      errorMessage = "Failed to load program guide."
    }
    isLoading = false
  }

  // MARK: - Sectioning logic

  nonisolated(unsafe) static let jstCalendar: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    cal.locale = Locale(identifier: "en_US")
    return cal
  }()

  nonisolated static func groupPastByDate(
    entries: [ProgramDTO],
    current: ProgramDTO?,
    now: Date = Date()
  ) -> [DateSection] {
    let timestamp = Int(now.timeIntervalSince1970)
    let cal = jstCalendar

    // Past = before now AND not the current program
    let pastEntries = entries.filter { entry in
      entry.time < timestamp && entry != current
    }

    // Group by JST calendar day
    var grouped: [(date: Date, programs: [ProgramDTO])] = []
    var currentDay: Date?
    var currentGroup: [ProgramDTO] = []

    for entry in pastEntries {
      let entryDate = Date(timeIntervalSince1970: TimeInterval(entry.time))
      let day = cal.startOfDay(for: entryDate)
      if day != currentDay {
        if let prevDay = currentDay, !currentGroup.isEmpty {
          grouped.append((date: prevDay, programs: currentGroup))
        }
        currentDay = day
        currentGroup = [entry]
      } else {
        currentGroup.append(entry)
      }
    }
    if let lastDay = currentDay, !currentGroup.isEmpty {
      grouped.append((date: lastDay, programs: currentGroup))
    }

    // Reverse: newest day first, within each day newest first
    let today = cal.startOfDay(for: now)
    let yesterday = cal.date(byAdding: .day, value: -1, to: today)!

    return grouped.reversed().map { dayGroup in
      let label: String
      if cal.isDate(dayGroup.date, inSameDayAs: today) {
        label = "Today"
      } else if cal.isDate(dayGroup.date, inSameDayAs: yesterday) {
        label = "Yesterday"
      } else {
        label = Self.sectionFormatter.string(from: dayGroup.date)
      }
      return DateSection(label: label, programs: dayGroup.programs.reversed())
    }
  }

  nonisolated(unsafe) private static let sectionFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "EEE, MMM d"
    f.timeZone = TimeZone(identifier: "Asia/Tokyo")
    f.locale = Locale(identifier: "en_US")
    return f
  }()
}

// MARK: - View

public struct ProgramListView: View {
  var viewModel: ProgramListViewModel
  var onPlayLive: () -> Void
  var onPlayVOD: (ProgramDTO) -> Void

  public init(
    viewModel: ProgramListViewModel,
    onPlayLive: @escaping () -> Void,
    onPlayVOD: @escaping (ProgramDTO) -> Void
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
          Button("Retry") { Task { await viewModel.loadPrograms() } }
        }
      } else {
        programList
      }
    }
    .task { await viewModel.loadPrograms() }
    .navigationTitle(viewModel.channelName)
  }

  private var programList: some View {
    List {
      nowSection
      upcomingSection
      pastSections
    }
  }

  // MARK: - Now section

  @ViewBuilder
  private var nowSection: some View {
    if let current = viewModel.currentProgram {
      Section("Now") {
        Button {
          onPlayLive()
        } label: {
          ProgramRow(entry: current, style: .live)
        }
        .buttonStyle(.plain)
      }
    }
  }

  // MARK: - Upcoming section

  @ViewBuilder
  private var upcomingSection: some View {
    let upcoming = viewModel.upcomingPrograms
    if !upcoming.isEmpty {
      Section("Upcoming") {
        ForEach(upcoming, id: \.time) { entry in
          ProgramRow(entry: entry, style: .upcoming)
        }
      }
    }
  }

  // MARK: - Past sections grouped by date

  @ViewBuilder
  private var pastSections: some View {
    ForEach(viewModel.pastByDate, id: \.label) { section in
      Section(section.label) {
        ForEach(section.programs, id: \.time) { entry in
          if entry.hasVOD {
            Button {
              onPlayVOD(entry)
            } label: {
              ProgramRow(entry: entry, style: .pastWithVOD)
            }
            .buttonStyle(.plain)
          } else {
            ProgramRow(entry: entry, style: .pastNoVOD)
          }
        }
      }
    }
  }
}

// MARK: - Program row

enum ProgramRowStyle {
  case live
  case upcoming
  case pastWithVOD
  case pastNoVOD
}

struct ProgramRow: View {
  let entry: ProgramDTO
  let style: ProgramRowStyle

  private static let jstFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    f.timeZone = TimeZone(identifier: "Asia/Tokyo")
    return f
  }()

  var body: some View {
    HStack(spacing: 12) {
      Text(Self.jstFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(entry.time))))
        .font(.caption.monospacedDigit())
        .foregroundStyle(timeColor)
        .frame(width: 44, alignment: .leading)

      Text(entry.title)
        .font(style == .live ? .body.bold() : .body)
        .foregroundStyle(titleColor)
        .lineLimit(2)

      Spacer()

      trailingBadge
    }
    .padding(.vertical, 2)
    .contentShape(Rectangle())
  }

  private var timeColor: Color {
    switch style {
    case .live: .red
    case .upcoming, .pastNoVOD: .secondary.opacity(0.5)
    case .pastWithVOD: .secondary
    }
  }

  private var titleColor: Color {
    switch style {
    case .live: .red
    case .upcoming, .pastNoVOD: .secondary.opacity(0.5)
    case .pastWithVOD: .primary
    }
  }

  @ViewBuilder
  private var trailingBadge: some View {
    switch style {
    case .live:
      Text("LIVE")
        .font(.caption2.bold())
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.red, in: Capsule())
    case .pastWithVOD:
      Image(systemName: "play.circle")
        .foregroundStyle(.blue)
    case .upcoming, .pastNoVOD:
      EmptyView()
    }
  }
}

// MARK: - Preview

#if DEBUG

private actor _NoOpAPIClient: APIClientProtocol {
  func get<T: Decodable & Sendable>(url: URL, headers: [String: String]) async throws -> T {
    fatalError("Preview stub")
  }
  func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(
    url: URL, headers: [String: String], body: Body
  ) async throws -> Response {
    fatalError("Preview stub")
  }
}

private func previewTimestamp(daysAgo: Int, hour: Int, minute: Int = 0) -> Int {
  var cal = Calendar(identifier: .gregorian)
  cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
  let now = Date()
  let day = cal.date(byAdding: .day, value: -daysAgo, to: cal.startOfDay(for: now))!
  let date = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
  return Int(date.timeIntervalSince1970)
}

#Preview("Program List") {
  let now = Int(Date().timeIntervalSince1970)
  let vm = ProgramListViewModel.__preview_create(
    channelName: "NHK総合",
    entries: [
      ProgramDTO(time: previewTimestamp(daysAgo: 2, hour: 9), title: "(水)朝のニュース", path: "/a"),
      ProgramDTO(time: previewTimestamp(daysAgo: 2, hour: 12), title: "(水)お昼のバラエティ", path: "/b"),
      ProgramDTO(time: previewTimestamp(daysAgo: 1, hour: 8), title: "(木)連続テレビ小説", path: "/c"),
      ProgramDTO(time: previewTimestamp(daysAgo: 1, hour: 12), title: "(木)ニュース", path: ""),
      ProgramDTO(time: previewTimestamp(daysAgo: 1, hour: 19), title: "(木)大河ドラマ", path: "/d"),
      ProgramDTO(time: previewTimestamp(daysAgo: 0, hour: 6), title: "おはよう日本", path: "/e"),
      ProgramDTO(time: previewTimestamp(daysAgo: 0, hour: 8), title: "連続テレビ小説「風よあらしよ」", path: "/f"),
      ProgramDTO(time: now - 1800, title: "NHKニュース", path: ""),
      ProgramDTO(time: now + 1800, title: "列島ニュース", path: ""),
      ProgramDTO(time: now + 5400, title: "きょうの料理", path: ""),
      ProgramDTO(time: now + 9000, title: "首都圏ネットワーク", path: ""),
    ]
  )
  NavigationStack {
    ProgramListView(viewModel: vm, onPlayLive: {}, onPlayVOD: { _ in })
  }
  .frame(width: 500, height: 700)
}

#endif
