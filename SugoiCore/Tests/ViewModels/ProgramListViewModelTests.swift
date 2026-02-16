import Foundation
import Testing

@testable import SugoiCore

@Suite("ProgramListViewModel")
struct ProgramListViewModelTests {
  /// Isolated UserDefaults per test to avoid cache leakage.
  static func ephemeralDefaults() -> UserDefaults {
    UserDefaults(suiteName: "test.\(UUID().uuidString)")!
  }

  static var testConfig: ProductConfig {
    ProductConfig(
      vmsHost: "http://live.yoitv.com:9083",
      vmsVodHost: nil, vmsUid: "UID", vmsLiveCid: "CID",
      vmsReferer: "http://play.yoitv.com", epgDays: 30, single: nil,
      vmsChannelListHost: nil, vmsLiveHost: nil, vmsRecordHost: nil, vmsLiveUid: nil
    )
  }

  @Test("Loads program entries successfully")
  @MainActor
  func loadPrograms() async {
    let mock = MockHTTPSession()
    let programJSON = """
      {
        "result": [{
          "id": "CH1",
          "name": "NHK",
          "record_epg": "[{\\"time\\":1000,\\"title\\":\\"Morning Show\\",\\"path\\":\\"/query/morning\\"},{\\"time\\":2000,\\"title\\":\\"Afternoon Show\\",\\"path\\":\\"\\"},{\\"time\\":9999999999,\\"title\\":\\"Future Show\\",\\"path\\":\\"\\"}]"
        }],
        "code": "OK"
      }
      """
    mock.requestHandler = { _ in
      let response = HTTPURLResponse(
        url: URL(string: "http://test.com")!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(programJSON.utf8))
    }

    let service = ProgramGuideService(apiClient: APIClient(session: mock.session))
    let vm = ProgramListViewModel(
      programGuideService: service, config: Self.testConfig,
      channelID: "CH1", channelName: "NHK",
      defaults: Self.ephemeralDefaults()
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
    let mock = MockHTTPSession()
    mock.requestHandler = { _ in
      let response = HTTPURLResponse(
        url: URL(string: "http://test.com")!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      let json = """
        {"result": [{"id": "CH1", "name": "NHK", "record_epg": "[{\\"time\\":9999,\\"title\\":\\"Replaced\\",\\"path\\":\\"\\"}]"}], "code": "OK"}
        """
      return (response, Data(json.utf8))
    }

    let service = ProgramGuideService(apiClient: APIClient(session: mock.session))
    let vm = ProgramListViewModel(
      programGuideService: service, config: Self.testConfig,
      channelID: "CH1", channelName: "NHK",
      defaults: Self.ephemeralDefaults()
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
    let mock = MockHTTPSession()
    let json = """
      {
        "result": [{
          "id": "CH1",
          "name": "NHK",
          "record_epg": "[{\\"time\\":1000,\\"title\\":\\"Past Show\\",\\"path\\":\\"/past\\"},{\\"time\\":\(Int(Date().timeIntervalSince1970) - 100),\\"title\\":\\"Current Show\\",\\"path\\":\\"\\"},{\\"time\\":\(Int(Date().timeIntervalSince1970) + 3600),\\"title\\":\\"Future Show\\",\\"path\\":\\"\\"}]"
        }],
        "code": "OK"
      }
      """
    mock.requestHandler = { _ in
      let response = HTTPURLResponse(
        url: URL(string: "http://test.com")!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(json.utf8))
    }

    let service = ProgramGuideService(apiClient: APIClient(session: mock.session))
    let vm = ProgramListViewModel(
      programGuideService: service, config: Self.testConfig,
      channelID: "CH1", channelName: "NHK",
      defaults: Self.ephemeralDefaults()
    )

    await vm.loadPrograms()

    #expect(vm.liveProgram != nil)
    #expect(vm.liveProgram?.title == "Current Show")
  }

  @Test("Load failure sets error message")
  @MainActor
  func loadFailure() async {
    let mock = MockHTTPSession()
    mock.requestHandler = { _ in
      throw URLError(.notConnectedToInternet)
    }

    let service = ProgramGuideService(apiClient: APIClient(session: mock.session))
    let vm = ProgramListViewModel(
      programGuideService: service, config: Self.testConfig,
      channelID: "CH1", channelName: "NHK",
      defaults: Self.ephemeralDefaults()
    )

    await vm.loadPrograms()

    #expect(vm.isLoading == false)
    #expect(vm.errorMessage == "Failed to load program guide.")
    #expect(vm.entries.isEmpty)
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

    let current = ProgramGuideService.liveProgram(in: entries, at: now)
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
    let current = ProgramGuideService.liveProgram(in: entries, at: now)
    let sections = ProgramListViewModel.groupPastByDate(entries: entries, current: current, now: now)

    #expect(sections.isEmpty)
  }

  @Test("Current program is excluded from past sections")
  func currentExcluded() {
    let now = Self.jstDate(month: 2, day: 14, hour: 15)
    let entries = [
      ProgramDTO(time: Self.jstTimestamp(month: 2, day: 14, hour: 14), title: "Current", path: ""),
    ]
    let current = ProgramGuideService.liveProgram(in: entries, at: now)
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
}
