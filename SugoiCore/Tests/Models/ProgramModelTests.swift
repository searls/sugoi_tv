import Foundation
import Testing

@testable import SugoiCore

@Suite("Program model")
struct ProgramModelTests {
  @Test("Initializes from ProgramDTO")
  func initFromDTO() {
    let dto = ProgramDTO(
      time: 1768338000,
      title: "NHKニュース おはよう日本",
      path: "/query/wtkmHz1XU-dOl-so_i2LJlsegL7gV3_laXirRbM5SSM="
    )
    let entry = Program(from: dto, channelID: "CH1")

    #expect(entry.channelID == "CH1")
    #expect(entry.title == "NHKニュース おはよう日本")
    #expect(entry.path == "/query/wtkmHz1XU-dOl-so_i2LJlsegL7gV3_laXirRbM5SSM=")
    #expect(entry.hasVOD == true)
    #expect(entry.startTime == Date(timeIntervalSince1970: 1768338000))
  }

  @Test("hasVOD is false when path is empty")
  func noVOD() {
    let entry = Program()
    entry.path = ""
    #expect(entry.hasVOD == false)

    entry.path = "/query/something"
    #expect(entry.hasVOD == true)
  }

  @Test("Formats time in JST")
  func jstFormatting() {
    // 2025-01-13 06:00:00 UTC = 2025-01-13 15:00:00 JST
    let dto = ProgramDTO(time: 1736748000, title: "Test", path: "")
    let entry = Program(from: dto, channelID: "CH1")
    #expect(entry.formattedTime == "15:00")
  }
}
