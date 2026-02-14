import Foundation
import Testing

@testable import SugoiCore

@Suite("EPGService")
struct EPGServiceTests {
  static let epgJSON = """
    {
      "result": [{
        "id": "CH1",
        "name": "NHK",
        "record_epg": "[{\\"time\\":1000,\\"title\\":\\"Past Show\\",\\"path\\":\\"/query/past\\"},{\\"time\\":2000,\\"title\\":\\"Current Show\\",\\"path\\":\\"\\"},{\\"time\\":9999999999,\\"title\\":\\"Future Show\\",\\"path\\":\\"\\"}]"
      }],
      "code": "OK"
    }
    """

  @Test("Fetches and parses EPG entries")
  func fetchEPG() async throws {
    let mock = MockHTTPSession()
    mock.requestHandler = { _ in
      let response = HTTPURLResponse(
        url: URL(string: "http://test.com")!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(Self.epgJSON.utf8))
    }

    let config = ProductConfig(
      vmsHost: "http://live.yoitv.com:9083",
      vmsVodHost: nil, vmsUid: "UID", vmsLiveCid: "CID",
      vmsReferer: "http://play.yoitv.com", epgDays: 30, single: nil,
      vmsChannelListHost: nil, vmsLiveHost: nil, vmsRecordHost: nil, vmsLiveUid: nil
    )

    let service = EPGService(apiClient: APIClient(session: mock.session))
    let entries = try await service.fetchEPG(config: config, channelID: "CH1")

    #expect(entries.count == 3)
    #expect(entries[0].title == "Past Show")
    #expect(entries[0].hasVOD == true)
    #expect(entries[1].hasVOD == false)
  }

  @Test("Finds current program by timestamp")
  func currentProgram() {
    let entries = [
      EPGEntryDTO(time: 1000, title: "Show A", path: "/a"),
      EPGEntryDTO(time: 2000, title: "Show B", path: ""),
      EPGEntryDTO(time: 3000, title: "Show C", path: ""),
    ]

    let current = EPGService.currentProgram(in: entries, at: Date(timeIntervalSince1970: 2500))
    #expect(current?.title == "Show B")

    let first = EPGService.currentProgram(in: entries, at: Date(timeIntervalSince1970: 1500))
    #expect(first?.title == "Show A")

    let before = EPGService.currentProgram(in: entries, at: Date(timeIntervalSince1970: 500))
    #expect(before == nil)
  }

  @Test("Finds upcoming programs")
  func upcomingPrograms() {
    let entries = [
      EPGEntryDTO(time: 1000, title: "Past", path: ""),
      EPGEntryDTO(time: 2000, title: "Now", path: ""),
      EPGEntryDTO(time: 3000, title: "Soon", path: ""),
      EPGEntryDTO(time: 4000, title: "Later", path: ""),
    ]

    let upcoming = EPGService.upcomingPrograms(
      in: entries, after: Date(timeIntervalSince1970: 2500), limit: 2
    )
    #expect(upcoming.count == 2)
    #expect(upcoming[0].title == "Soon")
    #expect(upcoming[1].title == "Later")
  }

  @Test("Finds VOD-available past programs")
  func vodAvailable() {
    let entries = [
      EPGEntryDTO(time: 1000, title: "With VOD", path: "/vod"),
      EPGEntryDTO(time: 2000, title: "No VOD", path: ""),
      EPGEntryDTO(time: 9999999999, title: "Future", path: "/future"),
    ]

    let vod = EPGService.vodAvailable(in: entries, before: Date(timeIntervalSince1970: 5000))
    #expect(vod.count == 1)
    #expect(vod[0].title == "With VOD")
  }
}
