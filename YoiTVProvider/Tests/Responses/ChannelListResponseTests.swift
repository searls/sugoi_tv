import Foundation
import Testing

@testable import YoiTVProvider
@testable import SugoiCore

@Suite("ChannelListResponse")
struct ChannelListResponseTests {
  static let channelJSON = """
    {
      "result": [
        {
          "id": "AA6EC2B2BC19EFE5FA44BE23187CDA63",
          "uid": "C2D9261F3D5753E74E97EB28FE2D8B26",
          "name": "NHK総合・東京",
          "description": "[HD]NHK General",
          "tags": "$LIVE_CAT_関東",
          "no": 101024,
          "timeshift": 1,
          "timeshift_len": 900,
          "epg_keep_days": 28,
          "state": 2,
          "running": 1,
          "playpath": "/query/s/Hqm-m7jqkFlA1CloJoaJZQ==",
          "live_type": "video"
        },
        {
          "id": "BB7FC3C3CD2A0FF6GB55CF34298EEB74",
          "name": "テレビ大阪",
          "tags": "$LIVE_CAT_関西, $LIVE_CAT_BS",
          "no": 201001,
          "playpath": "/query/s/TestPath=="
        }
      ],
      "code": "OK"
    }
    """

  @Test("Decodes channel list response")
  func decodesChannelList() throws {
    let data = Self.channelJSON.data(using: .utf8)!
    let response = try JSONDecoder().decode(ChannelListResponse.self, from: data)

    #expect(response.code == "OK")
    #expect(response.result.count == 2)

    let nhk = response.result[0]
    #expect(nhk.id == "AA6EC2B2BC19EFE5FA44BE23187CDA63")
    #expect(nhk.name == "NHK総合・東京")
    #expect(nhk.description == "[HD]NHK General")
    #expect(nhk.playpath == "/query/s/Hqm-m7jqkFlA1CloJoaJZQ==")
    #expect(nhk.no == 101024)
    #expect(nhk.running == 1)
    #expect(nhk.timeshift == 1)
    #expect(nhk.timeshiftLen == 900)
    #expect(nhk.epgKeepDays == 28)
    #expect(nhk.liveType == "video")
  }

  @Test("Parses single category from tags")
  func parseSingleCategory() throws {
    let data = Self.channelJSON.data(using: .utf8)!
    let response = try JSONDecoder().decode(ChannelListResponse.self, from: data)
    let nhk = response.result[0]

    #expect(nhk.categories == ["関東"])
    #expect(nhk.primaryCategory == "関東")
  }

  @Test("Parses multiple categories from comma-separated tags")
  func parseMultipleCategories() throws {
    let data = Self.channelJSON.data(using: .utf8)!
    let response = try JSONDecoder().decode(ChannelListResponse.self, from: data)
    let osaka = response.result[1]

    #expect(osaka.categories == ["関西", "BS"])
    #expect(osaka.primaryCategory == "関西")
  }

  @Test("Returns 'Others' when no LIVE_CAT tags")
  func noCategoryDefaultsToOthers() {
    let dto = ChannelDTO(
      id: "X", uid: nil, name: "Test", description: nil,
      tags: "some_other_tag", no: 1, timeshift: nil, timeshiftLen: nil,
      epgKeepDays: nil, state: nil, running: nil, playpath: "/test", liveType: nil
    )
    #expect(dto.primaryCategory == "Others")
    #expect(dto.categories.isEmpty)
  }

  @Test("Handles nil tags gracefully")
  func nilTags() {
    let dto = ChannelDTO(
      id: "X", uid: nil, name: "Test", description: nil,
      tags: nil, no: 1, timeshift: nil, timeshiftLen: nil,
      epgKeepDays: nil, state: nil, running: nil, playpath: "/test", liveType: nil
    )
    #expect(dto.primaryCategory == "Others")
    #expect(dto.categories.isEmpty)
  }

  @Test("Handles optional fields being absent in JSON")
  func handlesOptionalFields() throws {
    let minimalJSON = """
      {
        "result": [{"id": "X", "name": "Minimal", "no": 1, "playpath": "/test"}],
        "code": "OK"
      }
      """
    let data = minimalJSON.data(using: .utf8)!
    let response = try JSONDecoder().decode(ChannelListResponse.self, from: data)
    let ch = response.result[0]

    #expect(ch.uid == nil)
    #expect(ch.description == nil)
    #expect(ch.tags == nil)
    #expect(ch.running == nil)
    #expect(ch.timeshift == nil)
    #expect(ch.liveType == nil)
  }
}
