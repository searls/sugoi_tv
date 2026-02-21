import Foundation
import Testing

@testable import YoiTVProvider

@Suite("PlayRecordResponse")
struct PlayRecordResponseTests {
  static let responseJSON = """
    {
      "code": "OK",
      "data": [
        {
          "vid": "1813E2FB2946FB4176867F5AFB944899",
          "name": "ＤａｙＤａｙ．",
          "duration": 6271899,
          "pos": 701697,
          "platAt": 1770727745,
          "channelId": "CAD5FED3093396B3A4D49F326DE10CBD",
          "channelName": "日テレ",
          "playAt": 1770727043
        }
      ]
    }
    """

  @Test("Decodes play record list response")
  func decodesResponse() throws {
    let data = Self.responseJSON.data(using: .utf8)!
    let response = try JSONDecoder().decode(PlayRecordListResponse.self, from: data)

    #expect(response.code == "OK")
    #expect(response.data?.count == 1)

    let record = response.data![0]
    #expect(record.vid == "1813E2FB2946FB4176867F5AFB944899")
    #expect(record.name == "ＤａｙＤａｙ．")
    #expect(record.duration == 6271899)
    #expect(record.pos == 701697)
    #expect(record.channelId == "CAD5FED3093396B3A4D49F326DE10CBD")
    #expect(record.channelName == "日テレ")
    #expect(record.playAt == 1770727043)
    #expect(record.platAt == 1770727745)
  }

  @Test("Calculates progress correctly")
  func progressCalculation() {
    let record = PlayRecordDTO(
      vid: "X", name: "Test", duration: 1000, pos: 500,
      playAt: nil, platAt: nil, channelId: nil, channelName: nil
    )
    #expect(record.progress == 0.5)
  }

  @Test("Progress is zero when duration is zero")
  func zeroDurationProgress() {
    let record = PlayRecordDTO(
      vid: "X", name: "Test", duration: 0, pos: 100,
      playAt: nil, platAt: nil, channelId: nil, channelName: nil
    )
    #expect(record.progress == 0.0)
  }

  @Test("Progress is capped at 1.0")
  func cappedProgress() {
    let record = PlayRecordDTO(
      vid: "X", name: "Test", duration: 100, pos: 200,
      playAt: nil, platAt: nil, channelId: nil, channelName: nil
    )
    #expect(record.progress == 1.0)
  }
}
