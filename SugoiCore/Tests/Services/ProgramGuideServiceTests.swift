import Foundation
import Testing

@testable import SugoiCore

@Suite("ProgramGuideService")
struct ProgramGuideServiceTests {
  static let programJSON = """
    {
      "result": [{
        "id": "CH1",
        "name": "NHK",
        "record_epg": "[{\\"time\\":1000,\\"title\\":\\"Past Show\\",\\"path\\":\\"/query/past\\"},{\\"time\\":2000,\\"title\\":\\"Current Show\\",\\"path\\":\\"\\"},{\\"time\\":9999999999,\\"title\\":\\"Future Show\\",\\"path\\":\\"\\"}]"
      }],
      "code": "OK"
    }
    """

  @Test("Fetches and parses program entries")
  func fetchPrograms() async throws {
    let mock = MockHTTPSession()
    mock.requestHandler = { _ in
      let response = HTTPURLResponse(
        url: URL(string: "http://test.com")!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(Self.programJSON.utf8))
    }

    let config = ProductConfig(
      vmsHost: "http://live.yoitv.com:9083",
      vmsVodHost: nil, vmsUid: "UID", vmsLiveCid: "CID",
      vmsReferer: "http://play.yoitv.com", epgDays: 30, single: nil,
      vmsChannelListHost: nil, vmsLiveHost: nil, vmsRecordHost: nil, vmsLiveUid: nil
    )

    let service = ProgramGuideService(apiClient: APIClient(session: mock.session))
    let entries = try await service.fetchPrograms(config: config, channelID: "CH1")

    #expect(entries.count == 3)
    #expect(entries[0].title == "Past Show")
    #expect(entries[0].hasVOD == true)
    #expect(entries[1].hasVOD == false)
  }

  @Test("Finds current program by timestamp")
  func liveProgram() {
    let entries = [
      ProgramDTO(time: 1000, title: "Show A", path: "/a"),
      ProgramDTO(time: 2000, title: "Show B", path: ""),
      ProgramDTO(time: 3000, title: "Show C", path: ""),
    ]

    let current = ProgramGuideService.liveProgram(in: entries, at: Date(timeIntervalSince1970: 2500))
    #expect(current?.title == "Show B")

    let first = ProgramGuideService.liveProgram(in: entries, at: Date(timeIntervalSince1970: 1500))
    #expect(first?.title == "Show A")

    let before = ProgramGuideService.liveProgram(in: entries, at: Date(timeIntervalSince1970: 500))
    #expect(before == nil)
  }

  @Test("Finds upcoming programs")
  func upcomingPrograms() {
    let entries = [
      ProgramDTO(time: 1000, title: "Past", path: ""),
      ProgramDTO(time: 2000, title: "Now", path: ""),
      ProgramDTO(time: 3000, title: "Soon", path: ""),
      ProgramDTO(time: 4000, title: "Later", path: ""),
    ]

    let upcoming = ProgramGuideService.upcomingPrograms(
      in: entries, after: Date(timeIntervalSince1970: 2500), limit: 2
    )
    #expect(upcoming.count == 2)
    #expect(upcoming[0].title == "Soon")
    #expect(upcoming[1].title == "Later")
  }

  @Test("Finds VOD-available past programs")
  func vodAvailable() {
    let entries = [
      ProgramDTO(time: 1000, title: "With VOD", path: "/vod"),
      ProgramDTO(time: 2000, title: "No VOD", path: ""),
      ProgramDTO(time: 9999999999, title: "Future", path: "/future"),
    ]

    let vod = ProgramGuideService.vodAvailable(in: entries, before: Date(timeIntervalSince1970: 5000))
    #expect(vod.count == 1)
    #expect(vod[0].title == "With VOD")
  }
}
