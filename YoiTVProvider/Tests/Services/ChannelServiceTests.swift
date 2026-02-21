import Foundation
import Testing

@testable import YoiTVProvider
@testable import SugoiCore

@Suite("ChannelService")
struct ChannelServiceTests {
  static let channelsJSON = """
    {
      "result": [
        {"id": "CH1", "name": "NHK", "tags": "$LIVE_CAT_関東", "no": 1, "playpath": "/query/s/nhk", "running": 1, "timeshift": 1},
        {"id": "CH2", "name": "TBS", "tags": "$LIVE_CAT_関東", "no": 2, "playpath": "/query/s/tbs"},
        {"id": "CH3", "name": "MBS", "tags": "$LIVE_CAT_関西", "no": 3, "playpath": "/query/s/mbs"},
        {"id": "CH4", "name": "BS11", "tags": "$LIVE_CAT_BS", "no": 4, "playpath": "/query/s/bs11"}
      ],
      "code": "OK"
    }
    """

  static var testConfig: ProductConfig {
    ProductConfig(
      vmsHost: "http://live.yoitv.com:9083",
      vmsVodHost: nil, vmsUid: "UID", vmsLiveCid: "CID",
      vmsReferer: "http://play.yoitv.com", epgDays: nil, single: nil,
      vmsChannelListHost: nil, vmsLiveHost: nil, vmsRecordHost: nil, vmsLiveUid: nil
    )
  }

  @Test("Fetches and parses channel list")
  func fetchChannels() async throws {
    let mock = MockHTTPSession()
    mock.requestHandler = { _ in
      let response = HTTPURLResponse(
        url: URL(string: "http://test.com")!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(Self.channelsJSON.utf8))
    }

    let service = ChannelService(apiClient: APIClient(session: mock.session), config: Self.testConfig)
    let channels = try await service.fetchChannels()

    #expect(channels.count == 4)
    #expect(channels[0].name == "NHK")
    #expect(channels[0].primaryCategory == "関東")
  }

  @Test("Groups channels by category in correct order")
  func groupByCategory() {
    let channels = [
      ChannelDTO(id: "1", uid: nil, name: "NHK", description: nil, tags: "$LIVE_CAT_関東", no: 1, timeshift: nil, timeshiftLen: nil, epgKeepDays: nil, state: nil, running: nil, playpath: "/a", liveType: nil),
      ChannelDTO(id: "2", uid: nil, name: "MBS", description: nil, tags: "$LIVE_CAT_関西", no: 2, timeshift: nil, timeshiftLen: nil, epgKeepDays: nil, state: nil, running: nil, playpath: "/b", liveType: nil),
      ChannelDTO(id: "3", uid: nil, name: "BS11", description: nil, tags: "$LIVE_CAT_BS", no: 3, timeshift: nil, timeshiftLen: nil, epgKeepDays: nil, state: nil, running: nil, playpath: "/c", liveType: nil),
      ChannelDTO(id: "4", uid: nil, name: "Other", description: nil, tags: nil, no: 4, timeshift: nil, timeshiftLen: nil, epgKeepDays: nil, state: nil, running: nil, playpath: "/d", liveType: nil),
    ]

    let groups = channels.groupedByCategory()
    #expect(groups.count == 4)
    #expect(groups[0].category == "関東")
    #expect(groups[1].category == "関西")
    #expect(groups[2].category == "BS")
    #expect(groups[3].category == "Others")
  }
}
