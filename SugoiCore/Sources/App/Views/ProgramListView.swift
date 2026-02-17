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
  var entries: [ProgramDTO] = [] {
    didSet { recomputeDerivedState() }
  }
  var isLoading: Bool = false
  var errorMessage: String?
  var channelName: String = ""

  private(set) var liveProgram: ProgramDTO?
  private(set) var upcomingPrograms: [ProgramDTO] = []
  private(set) var pastByDate: [DateSection] = []

  private let programGuideService: ProgramGuideService
  private let config: ProductConfig
  let channelID: String

  private var cacheKey: String { "cachedPrograms_\(channelID)" }

  public init(programGuideService: ProgramGuideService, config: ProductConfig, channelID: String, channelName: String) {
    self.programGuideService = programGuideService
    self.config = config
    self.channelID = channelID
    self.channelName = channelName
    loadCachedPrograms()
    recomputeDerivedState()
  }

  private func loadCachedPrograms() {
    guard let cached = DiskCache.load(key: cacheKey, as: [ProgramDTO].self),
          !cached.isEmpty else { return }
    entries = cached
  }

  private func cachePrograms(_ programs: [ProgramDTO]) async {
    await DiskCache.save(key: cacheKey, value: programs)
  }

  private func recomputeDerivedState() {
    liveProgram = ProgramGuideService.liveProgram(in: entries)
    upcomingPrograms = ProgramGuideService.upcomingPrograms(in: entries, limit: 5)
    pastByDate = Self.groupPastByDate(entries: entries, current: liveProgram)
  }

  #if DEBUG
  /// Preview-only factory that creates a ViewModel with pre-loaded entries (no service needed).
  static func __preview_create(channelName: String, entries: [ProgramDTO]) -> ProgramListViewModel {
    let vm = ProgramListViewModel(
      programGuideService: ProgramGuideService(apiClient: _NoOpAPIClient()),
      config: try! JSONDecoder().decode(ProductConfig.self, from: Data(#"{"vms_host":"x","vms_uid":"x","vms_live_cid":"x","vms_referer":"x"}"#.utf8)),
      channelID: "preview_\(UUID().uuidString)",
      channelName: channelName
    )
    vm.entries = entries
    return vm
  }
  #endif

  private var lastFetchTime: Date?
  private let refreshInterval: TimeInterval = 3600 // 1 hour

  func loadPrograms() async {
    // Only fetch from network at most once per hour — program data changes
    // very rarely, and re-fetching + re-rendering hundreds of rows on every
    // sidebar show (NavigationSplitView recreates sidebar content) blocks
    // the main thread.
    if let lastFetch = lastFetchTime,
       Date().timeIntervalSince(lastFetch) < refreshInterval,
       !entries.isEmpty {
      return
    }
    lastFetchTime = Date()
    let showSpinner = entries.isEmpty
    if showSpinner { isLoading = true }
    errorMessage = nil
    do {
      let fresh = try await programGuideService.fetchPrograms(config: config, channelID: channelID)
      entries = fresh
      await cachePrograms(fresh)
    } catch {
      if entries.isEmpty {
        errorMessage = "Failed to load program guide."
      }
    }
    if showSpinner { isLoading = false }
  }

  // MARK: - Sectioning logic

  nonisolated static let jstCalendar: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    cal.locale = Locale(identifier: "en_US")
    return cal
  }()

  /// Maximum number of past days to display in the program list.
  /// The full 30-day EPG is still fetched and cached — this only limits
  /// how many days of rows the List renders, which directly affects
  /// main-thread layout cost during sidebar animations.
  nonisolated static let maxPastDays = 5

  nonisolated static func groupPastByDate(
    entries: [ProgramDTO],
    current: ProgramDTO?,
    now: Date = Date()
  ) -> [DateSection] {
    let timestamp = Int(now.timeIntervalSince1970)
    let cutoff = timestamp - (maxPastDays * 86400)
    let cal = jstCalendar

    // Past = before now AND not the current program, capped to maxPastDays
    let pastEntries = entries.filter { entry in
      entry.time < timestamp && entry.time >= cutoff && entry != current
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

  nonisolated private static let sectionFormatter: DateFormatter = {
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
  /// ID of the currently-playing program, or nil when playing live.
  var playingProgramID: String?
  var onPlayLive: () -> Void
  var onPlayVOD: (ProgramDTO) -> Void
  /// Toggle this from the parent to request focus on the program list.
  var focusTrigger: Bool = false

  @State private var selectedProgramID: String?
  @FocusState private var listFocused: Bool

  public init(
    viewModel: ProgramListViewModel,
    playingProgramID: String? = nil,
    onPlayLive: @escaping () -> Void,
    onPlayVOD: @escaping (ProgramDTO) -> Void,
    focusTrigger: Bool = false,
    onBack: (() -> Void)? = nil,
    channelDescription: String? = nil
  ) {
    self.viewModel = viewModel
    self.playingProgramID = playingProgramID
    self.onPlayLive = onPlayLive
    self.onPlayVOD = onPlayVOD
    self.focusTrigger = focusTrigger
    self.onBack = onBack
    self.channelDescription = channelDescription
  }

  var onBack: (() -> Void)?
  var channelDescription: String?

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
    .task {
      NSLog("⏱ ProgramList: %d entries, %d sections", viewModel.entries.count, viewModel.pastByDate.count)
      await viewModel.loadPrograms()
    }
  }

  private var playingOrLiveID: String? {
    playingProgramID ?? viewModel.liveProgram?.id
  }

  private var programList: some View {
    List(selection: $selectedProgramID) {
      backHeader
      upcomingSection
      liveSection
      pastSections
    }
    .focused($listFocused)
    .focusEffectDisabled()
    .listStyle(.sidebar)
    .onKeyPress(.return) {
      guard let id = selectedProgramID else { return .ignored }
      if id == viewModel.liveProgram?.id {
        onPlayLive()
        return .handled
      }
      if let program = viewModel.entries.first(where: { $0.id == id }),
         program.hasVOD {
        onPlayVOD(program)
        return .handled
      }
      return .ignored
    }
    .onAppear {
      selectPlaying()
    }
    .onChange(of: focusTrigger) { _, _ in
      selectPlaying()
    }
    .onChange(of: viewModel.liveProgram?.id) { _, _ in
      if selectedProgramID == nil {
        selectPlaying()
      }
    }
  }

  private func selectPlaying() {
    if let target = playingOrLiveID {
      selectedProgramID = target
    }
    // Defer focus — the List may not be ready to accept focus during sidebar animation
    DispatchQueue.main.async {
      listFocused = true
    }
  }

  // MARK: - Back header

  @ViewBuilder
  private var backHeader: some View {
    if let onBack {
      HStack(spacing: 12) {
        Button(action: onBack) {
          Image(systemName: "chevron.backward")
            .font(.body.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 32, height: 32)
            .background(.fill.tertiary, in: Circle())
        }
        .buttonStyle(.plain)

        VStack(alignment: .leading, spacing: 2) {
          Text(viewModel.channelName)
            .font(.title2.bold())
          if let desc = channelDescription, !desc.isEmpty {
            Text(desc)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
      .listRowSeparator(.hidden)
      .listRowBackground(Color.clear)
      .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
    }
  }

  // MARK: - Live section

  @ViewBuilder
  private var liveSection: some View {
    if let current = viewModel.liveProgram {
      Section("Live") {
        ProgramRow(entry: current, isLive: true, isPlaying: playingProgramID == nil)
          .listRowBackground(playingProgramID == nil ? Color.accentColor.opacity(0.15) : nil)
          .simultaneousGesture(TapGesture().onEnded { onPlayLive() })
          .tag(current.id)
      }
    }
  }

  // MARK: - Upcoming section

  @ViewBuilder
  private var upcomingSection: some View {
    let upcoming = viewModel.upcomingPrograms.prefix(2)
    if !upcoming.isEmpty {
      Section("Upcoming") {
        ForEach(upcoming) { entry in
          ProgramRow(entry: entry, dimmed: true)
            .tag(entry.id)
        }
      }
    }
  }

  // MARK: - Past sections grouped by date

  @ViewBuilder
  private var pastSections: some View {
    ForEach(viewModel.pastByDate, id: \.label) { section in
      Section(section.label) {
        ForEach(section.programs) { entry in
          let playing = playingProgramID == entry.id
          ProgramRow(entry: entry, hasVOD: entry.hasVOD, isPlaying: playing)
            .listRowBackground(playing ? Color.accentColor.opacity(0.15) : nil)
            .simultaneousGesture(TapGesture().onEnded {
              if entry.hasVOD { onPlayVOD(entry) }
            })
            .tag(entry.id)
        }
      }
    }
  }
}

// MARK: - Program row

struct ProgramRow: View {
  let entry: ProgramDTO
  var isLive: Bool = false
  var hasVOD: Bool = false
  var isPlaying: Bool = false
  var dimmed: Bool = false

  private static let jstFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    f.timeZone = TimeZone(identifier: "Asia/Tokyo")
    return f
  }()

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 4) {
        Text(Self.jstFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(entry.time))))
          .font(.caption.monospacedDigit())
          .foregroundStyle(isLive ? .red : .secondary)
        if isLive {
          Circle().fill(.red).frame(width: 6, height: 6)
        }
        if isPlaying {
          Image(systemName: "speaker.wave.2.fill")
            .font(.caption2)
            .foregroundStyle(.primary)
            .symbolEffect(.variableColor.iterative, isActive: true)
        }
      }

      Text(entry.title)
        .font(isLive ? .body.bold() : .body)
        .foregroundStyle(titleColor)
        .lineLimit(2)
    }
    .padding(.vertical, 2)
    .contentShape(Rectangle())
  }

  private var titleColor: Color {
    if isLive { return .red }
    if dimmed || (!hasVOD && !isLive) { return .secondary.opacity(0.5) }
    return .primary
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
