import Foundation
import Testing

@testable import SugoiCore

@Suite("ProgramListViewModel")
struct ProgramListViewModelTests {
  private func makeMock(programs: [ProgramDTO] = [], channelID: String = "CH1") -> MockTVProvider {
    let mock = MockTVProvider(isAuthenticated: true)
    mock.setPrograms(programs, for: channelID)
    return mock
  }

  @Test("Loads program entries successfully")
  @MainActor
  func loadPrograms() async {
    let programs = [
      ProgramDTO(time: 1000, title: "Morning Show", path: "/query/morning"),
      ProgramDTO(time: 2000, title: "Afternoon Show", path: ""),
      ProgramDTO(time: 9999999999, title: "Future Show", path: ""),
    ]
    let channelID = "load_\(UUID())"
    let mock = makeMock(programs: programs, channelID: channelID)
    let vm = ProgramListViewModel(
      provider: mock,
      channelID: channelID, channelName: "NHK"
    )

    await vm.loadPrograms()

    #expect(vm.isLoading == false)
    #expect(vm.errorMessage == nil)
    #expect(vm.entries.count == 3)
    #expect(vm.channelName == "NHK")
  }

  @Test("Background refresh updates entries even when already populated")
  @MainActor
  func refreshesWhenPopulated() async {
    let channelID = "refresh_\(UUID())"
    let mock = makeMock(
      programs: [ProgramDTO(time: 9999, title: "Replaced", path: "")],
      channelID: channelID
    )
    let vm = ProgramListViewModel(
      provider: mock,
      channelID: channelID, channelName: "NHK"
    )

    // Pre-populate entries
    vm.entries = [ProgramDTO(time: 1000, title: "Existing", path: "")]

    await vm.loadPrograms()

    // Background refresh replaces entries with fresh data
    #expect(vm.entries.count == 1)
    #expect(vm.entries[0].title == "Replaced")
  }

  @Test("Current program is detected")
  @MainActor
  func liveProgram() async {
    let now = Int(Date().timeIntervalSince1970)
    let channelID = "live_\(UUID())"
    let programs = [
      ProgramDTO(time: 1000, title: "Past Show", path: "/past"),
      ProgramDTO(time: now - 100, title: "Current Show", path: ""),
      ProgramDTO(time: now + 3600, title: "Future Show", path: ""),
    ]
    let mock = makeMock(programs: programs, channelID: channelID)
    let vm = ProgramListViewModel(
      provider: mock,
      channelID: channelID, channelName: "NHK"
    )

    await vm.loadPrograms()

    #expect(vm.liveProgram != nil)
    #expect(vm.liveProgram?.title == "Current Show")
  }

  @Test("Load failure sets error message")
  @MainActor
  func loadFailure() async {
    let mock = MockTVProvider(isAuthenticated: true)
    mock.setShouldFailFetch(true)
    let vm = ProgramListViewModel(
      provider: mock,
      channelID: "fail_\(UUID())", channelName: "NHK"
    )

    await vm.loadPrograms()

    #expect(vm.isLoading == false)
    #expect(vm.errorMessage == "Failed to load program guide.")
    #expect(vm.entries.isEmpty)
  }

}

// MARK: - Derived state tests

@Suite("ProgramListViewModel derived state")
struct ProgramListViewModelDerivedStateTests {
  @Test("Setting entries updates liveProgram")
  @MainActor
  func entriesUpdateLiveProgram() {
    let now = Int(Date().timeIntervalSince1970)
    let mock = MockTVProvider(isAuthenticated: true)
    let vm = ProgramListViewModel(
      provider: mock,
      channelID: "derived_\(UUID())", channelName: "NHK"
    )

    #expect(vm.liveProgram == nil)

    vm.entries = [
      ProgramDTO(time: now - 100, title: "Current", path: ""),
      ProgramDTO(time: now + 3600, title: "Future", path: ""),
    ]

    #expect(vm.liveProgram?.title == "Current")
  }

  @Test("Setting entries updates upcomingPrograms")
  @MainActor
  func entriesUpdateUpcoming() {
    let now = Int(Date().timeIntervalSince1970)
    let mock = MockTVProvider(isAuthenticated: true)
    let vm = ProgramListViewModel(
      provider: mock,
      channelID: "derived_\(UUID())", channelName: "NHK"
    )

    vm.entries = [
      ProgramDTO(time: now - 100, title: "Current", path: ""),
      ProgramDTO(time: now + 1800, title: "Next", path: ""),
      ProgramDTO(time: now + 3600, title: "Later", path: ""),
    ]

    #expect(vm.upcomingPrograms.count == 2)
    #expect(vm.upcomingPrograms[0].title == "Next")
    #expect(vm.upcomingPrograms[1].title == "Later")
  }

  @Test("Setting entries updates pastByDate")
  @MainActor
  func entriesUpdatePastByDate() {
    let now = Int(Date().timeIntervalSince1970)
    let mock = MockTVProvider(isAuthenticated: true)
    let vm = ProgramListViewModel(
      provider: mock,
      channelID: "derived_\(UUID())", channelName: "NHK"
    )

    vm.entries = [
      ProgramDTO(time: now - 7200, title: "Earlier", path: "/a"),
      ProgramDTO(time: now - 100, title: "Current", path: ""),
      ProgramDTO(time: now + 3600, title: "Future", path: ""),
    ]

    #expect(!vm.pastByDate.isEmpty)
    let allPast = vm.pastByDate.flatMap(\.programs)
    #expect(allPast.contains(where: { $0.title == "Earlier" }))
    // Current program is excluded from past
    #expect(!allPast.contains(where: { $0.title == "Current" }))
  }

  @Test("Clearing entries clears derived state")
  @MainActor
  func clearingEntriesClearsDerived() {
    let now = Int(Date().timeIntervalSince1970)
    let mock = MockTVProvider(isAuthenticated: true)
    let vm = ProgramListViewModel(
      provider: mock,
      channelID: "derived_\(UUID())", channelName: "NHK"
    )

    vm.entries = [
      ProgramDTO(time: now - 100, title: "Current", path: ""),
      ProgramDTO(time: now + 1800, title: "Next", path: ""),
    ]
    #expect(vm.liveProgram != nil)

    vm.entries = []
    #expect(vm.liveProgram == nil)
    #expect(vm.upcomingPrograms.isEmpty)
    #expect(vm.pastByDate.isEmpty)
  }
}

// MARK: - Sectioning logic tests

@Suite("ProgramListViewModel.groupPastByDate")
struct ProgramListViewModelSectioningTests {
  /// Helper: creates a Unix timestamp for a given JST date/time.
  /// month/day/hour/minute in Asia/Tokyo timezone.
  private static func jstTimestamp(
    year: Int = 2026, month: Int, day: Int, hour: Int, minute: Int = 0
  ) -> Int {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    let comps = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
    return Int(cal.date(from: comps)!.timeIntervalSince1970)
  }

  private static func jstDate(
    year: Int = 2026, month: Int, day: Int, hour: Int, minute: Int = 0
  ) -> Date {
    Date(timeIntervalSince1970: TimeInterval(jstTimestamp(year: year, month: month, day: day, hour: hour, minute: minute)))
  }

  @Test("Groups past programs by JST calendar day, newest day first")
  func groupsByDay() {
    let now = Self.jstDate(month: 2, day: 14, hour: 15) // Feb 14 15:00 JST

    let entries = [
      ProgramDTO(time: Self.jstTimestamp(month: 2, day: 12, hour: 9), title: "Day12 Morning", path: "/a"),
      ProgramDTO(time: Self.jstTimestamp(month: 2, day: 12, hour: 14), title: "Day12 Afternoon", path: "/b"),
      ProgramDTO(time: Self.jstTimestamp(month: 2, day: 13, hour: 10), title: "Day13 Morning", path: ""),
      ProgramDTO(time: Self.jstTimestamp(month: 2, day: 13, hour: 20), title: "Day13 Evening", path: "/c"),
      ProgramDTO(time: Self.jstTimestamp(month: 2, day: 14, hour: 8), title: "Today Morning", path: "/d"),
      ProgramDTO(time: Self.jstTimestamp(month: 2, day: 14, hour: 14), title: "Current", path: ""), // current
      ProgramDTO(time: Self.jstTimestamp(month: 2, day: 14, hour: 18), title: "Future", path: ""),
    ]

    let current = entries.liveProgram(at: now)
    let sections = ProgramListViewModel.groupPastByDate(entries: entries, current: current, now: now)

    // 3 days of past content (today, yesterday, Wed Feb 12)
    #expect(sections.count == 3)

    // Newest day first
    #expect(sections[0].label == "Today")
    #expect(sections[1].label == "Yesterday")
    #expect(sections[2].label.contains("Feb"))

    // Today has 1 past program (morning), current is excluded
    #expect(sections[0].programs.count == 1)
    #expect(sections[0].programs[0].title == "Today Morning")

    // Yesterday has 2 programs, newest first
    #expect(sections[1].programs.count == 2)
    #expect(sections[1].programs[0].title == "Day13 Evening")
    #expect(sections[1].programs[1].title == "Day13 Morning")

    // Feb 12 has 2 programs, newest first
    #expect(sections[2].programs.count == 2)
    #expect(sections[2].programs[0].title == "Day12 Afternoon")
    #expect(sections[2].programs[1].title == "Day12 Morning")
  }

  @Test("Returns empty when no past programs exist")
  func emptyWhenNoPast() {
    let now = Self.jstDate(month: 2, day: 14, hour: 15)
    let entries = [
      ProgramDTO(time: Self.jstTimestamp(month: 2, day: 14, hour: 14), title: "Current", path: ""),
      ProgramDTO(time: Self.jstTimestamp(month: 2, day: 14, hour: 18), title: "Future", path: ""),
    ]
    let current = entries.liveProgram(at: now)
    let sections = ProgramListViewModel.groupPastByDate(entries: entries, current: current, now: now)

    #expect(sections.isEmpty)
  }

  @Test("Current program is excluded from past sections")
  func currentExcluded() {
    let now = Self.jstDate(month: 2, day: 14, hour: 15)
    let entries = [
      ProgramDTO(time: Self.jstTimestamp(month: 2, day: 14, hour: 14), title: "Current", path: ""),
    ]
    let current = entries.liveProgram(at: now)
    let sections = ProgramListViewModel.groupPastByDate(entries: entries, current: current, now: now)

    #expect(sections.isEmpty)
  }

  @Test("Section labels use English locale")
  func englishLabels() {
    let now = Self.jstDate(month: 2, day: 14, hour: 15)
    let entries = [
      ProgramDTO(time: Self.jstTimestamp(month: 2, day: 11, hour: 10), title: "Wed show", path: "/a"),
    ]
    let sections = ProgramListViewModel.groupPastByDate(entries: entries, current: nil, now: now)

    #expect(sections.count == 1)
    // Should be English day-of-week, e.g. "Wed, Feb 11"
    #expect(sections[0].label.hasPrefix("Wed"))
  }

  @Test("Initial display limit is min(7 days, 100 items)")
  func initialLimit() {
    // 40 programs/day × 30 days = busy channel
    // 7 days × 40 = 280, capped to 100
    let now = Self.jstDate(month: 2, day: 14, hour: 15)
    var busyEntries: [ProgramDTO] = []
    for day in 0..<30 {
      for slot in 0..<40 {
        let hour = 6 + (slot % 18)
        let minute = (slot / 18) * 30
        busyEntries.append(ProgramDTO(
          time: Self.jstTimestamp(month: 2, day: max(1, 14 - day), hour: hour, minute: minute),
          title: "Busy \(day)-\(slot)",
          path: "/p\(day)_\(slot)"
        ))
      }
    }
    busyEntries.sort { $0.time < $1.time }
    let busySections = ProgramListViewModel.groupPastByDate(entries: busyEntries, current: nil, now: now)
    let busyLimit = ProgramListViewModel.initialLimit(for: busySections, now: now)
    #expect(busyLimit == ProgramListViewModel.pageSize) // capped at 100

    // 5 programs/day × 30 days = quiet channel
    // 7 days × 5 = 35, under 100 so not capped
    var quietEntries: [ProgramDTO] = []
    for day in 0..<30 {
      for slot in 0..<5 {
        quietEntries.append(ProgramDTO(
          time: Self.jstTimestamp(month: 2, day: max(1, 14 - day), hour: 8 + slot * 3),
          title: "Quiet \(day)-\(slot)",
          path: "/q\(day)_\(slot)"
        ))
      }
    }
    quietEntries.sort { $0.time < $1.time }
    let quietSections = ProgramListViewModel.groupPastByDate(entries: quietEntries, current: nil, now: now)
    let quietLimit = ProgramListViewModel.initialLimit(for: quietSections, now: now)
    #expect(quietLimit > 0)
    #expect(quietLimit < ProgramListViewModel.pageSize) // under 100
    #expect(quietLimit == 35) // exactly 7 days × 5/day
  }

  @Test("displayedPastByDate paginates and showMorePast loads next page")
  @MainActor
  func pastPagination() {
    let mock = MockTVProvider(isAuthenticated: true)
    let vm = ProgramListViewModel(
      provider: mock,
      channelID: "page_\(UUID())",
      channelName: "NHK"
    )

    // 40 programs/day × 10 days = 400 total past programs
    let now = Date()
    var entries: [ProgramDTO] = []
    for day in 0..<10 {
      for slot in 0..<40 {
        let ts = Int(now.timeIntervalSince1970) - ((day * 86400) + (slot + 1) * 600)
        entries.append(ProgramDTO(time: ts, title: "P\(day)-\(slot)", path: "/p\(day)_\(slot)"))
      }
    }
    entries.sort { $0.time < $1.time }
    // Add a current program so it's excluded from past
    entries.append(ProgramDTO(time: Int(now.timeIntervalSince1970) - 100, title: "Current", path: ""))
    vm.entries = entries

    let totalPast = vm.pastByDate.reduce(0) { $0 + $1.programs.count }
    #expect(totalPast == 400)

    // Initial page should be capped at pageSize (7 days × 40 = 280 > 100)
    let page1 = vm.displayedPastByDate.reduce(0) { $0 + $1.programs.count }
    #expect(page1 == ProgramListViewModel.pageSize)
    #expect(vm.hasMorePast)

    // Load more
    vm.showMorePast()
    let page2 = vm.displayedPastByDate.reduce(0) { $0 + $1.programs.count }
    #expect(page2 == ProgramListViewModel.pageSize * 2)
    #expect(vm.hasMorePast)

    // Reset goes back to initial
    vm.resetPastDisplay()
    let reset = vm.displayedPastByDate.reduce(0) { $0 + $1.programs.count }
    #expect(reset == ProgramListViewModel.pageSize)
  }
}
