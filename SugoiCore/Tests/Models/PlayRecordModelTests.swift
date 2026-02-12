import Foundation
import Testing

@testable import SugoiCore

@Suite("PlayRecord model")
struct PlayRecordModelTests {
  @Test("Initializes from PlayRecordDTO")
  func initFromDTO() {
    let dto = PlayRecordDTO(
      vid: "V1", name: "ＤａｙＤａｙ．",
      duration: 6271899, pos: 701697,
      playAt: 1770727043, platAt: 1770727745,
      channelId: "C1", channelName: "日テレ"
    )
    let record = PlayRecord(from: dto)

    #expect(record.vid == "V1")
    #expect(record.name == "ＤａｙＤａｙ．")
    #expect(record.durationMs == 6271899)
    #expect(record.positionMs == 701697)
    #expect(record.channelID == "C1")
    #expect(record.channelName == "日テレ")
    #expect(record.playedAt == Date(timeIntervalSince1970: 1770727043))
  }

  @Test("Falls back to platAt when playAt is nil")
  func platAtFallback() {
    let dto = PlayRecordDTO(
      vid: "V1", name: "Test", duration: 1000, pos: 500,
      playAt: nil, platAt: 1770727745, channelId: nil, channelName: nil
    )
    let record = PlayRecord(from: dto)
    #expect(record.playedAt == Date(timeIntervalSince1970: 1770727745))
  }

  @Test("Progress calculation")
  func progress() {
    let record = PlayRecord()
    record.durationMs = 1000
    record.positionMs = 500
    #expect(record.progress == 0.5)

    record.durationMs = 0
    #expect(record.progress == 0.0)

    record.durationMs = 100
    record.positionMs = 200
    #expect(record.progress == 1.0)
  }

  @Test("Duration formatting")
  func formatting() {
    #expect(PlayRecord.formatMilliseconds(0) == "0:00")
    #expect(PlayRecord.formatMilliseconds(61000) == "1:01")
    #expect(PlayRecord.formatMilliseconds(3661000) == "1:01:01")
    #expect(PlayRecord.formatMilliseconds(6271899) == "1:44:31")
  }
}
