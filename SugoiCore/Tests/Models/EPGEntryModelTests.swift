import Foundation
import Testing

@testable import SugoiCore

@Suite("EPGEntry model")
struct EPGEntryModelTests {
  @Test("Initializes from EPGEntryDTO")
  func initFromDTO() {
    let dto = EPGEntryDTO(
      time: 1768338000,
      title: "NHKニュース おはよう日本",
      path: "/query/wtkmHz1XU-dOl-so_i2LJlsegL7gV3_laXirRbM5SSM="
    )
    let entry = EPGEntry(from: dto, channelID: "CH1")

    #expect(entry.channelID == "CH1")
    #expect(entry.title == "NHKニュース おはよう日本")
    #expect(entry.path == "/query/wtkmHz1XU-dOl-so_i2LJlsegL7gV3_laXirRbM5SSM=")
    #expect(entry.hasVOD == true)
    #expect(entry.startTime == Date(timeIntervalSince1970: 1768338000))
  }

  @Test("hasVOD is false when path is empty")
  func noVOD() {
    let entry = EPGEntry()
    entry.path = ""
    #expect(entry.hasVOD == false)

    entry.path = "/query/something"
    #expect(entry.hasVOD == true)
  }

  @Test("Formats time in JST")
  func jstFormatting() {
    // 2025-01-13 06:00:00 UTC = 2025-01-13 15:00:00 JST
    let dto = EPGEntryDTO(time: 1736748000, title: "Test", path: "")
    let entry = EPGEntry(from: dto, channelID: "CH1")
    #expect(entry.formattedTime == "15:00")
  }
}
