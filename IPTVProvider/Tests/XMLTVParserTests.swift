import Foundation
import Testing

@testable import IPTVProvider

@Suite("XMLTVParser")
struct XMLTVParserTests {
  let fixtureData: Data

  init() throws {
    let url = Bundle.module.url(forResource: "sample", withExtension: "xml", subdirectory: "Fixtures")!
    fixtureData = try Data(contentsOf: url)
  }

  @Test("Groups programs by channel ID")
  func groupsByChannel() {
    let result = XMLTVParser.parse(fixtureData)
    #expect(result.keys.count == 2)
    #expect(result["NHK.jp"]?.count == 2)
    #expect(result["TBS.jp"]?.count == 1)
  }

  @Test("Parses program titles")
  func titles() {
    let result = XMLTVParser.parse(fixtureData)
    let nhkPrograms = result["NHK.jp"]!
    #expect(nhkPrograms[0].title == "Morning News")
    #expect(nhkPrograms[1].title == "Weather Report")
  }

  @Test("Parses timestamps correctly")
  func timestamps() {
    let result = XMLTVParser.parse(fixtureData)
    let program = result["NHK.jp"]![0]
    // 20250101090000 +0900 = 20250101000000 UTC
    let expected = DateComponents(
      calendar: Calendar(identifier: .gregorian),
      timeZone: TimeZone(identifier: "UTC"),
      year: 2025, month: 1, day: 1, hour: 0, minute: 0
    ).date!
    #expect(program.start == expected)
  }

  @Test("Channel IDs match programme attributes")
  func channelIDs() {
    let result = XMLTVParser.parse(fixtureData)
    let tbsProgram = result["TBS.jp"]![0]
    #expect(tbsProgram.channelID == "TBS.jp")
  }

  @Test("Empty data returns empty dictionary")
  func emptyData() {
    let result = XMLTVParser.parse(Data())
    #expect(result.isEmpty)
  }
}
