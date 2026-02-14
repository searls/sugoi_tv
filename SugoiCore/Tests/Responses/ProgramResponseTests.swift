import Foundation
import Testing

@testable import SugoiCore

@Suite("ProgramResponse")
struct ProgramResponseTests {
  static let programJSON = """
    {
      "result": [{
        "id": "AA6EC2B2BC19EFE5FA44BE23187CDA63",
        "name": "NHK総合・東京",
        "record_epg": "[{\\"time\\":1768338000,\\"title\\":\\"NHKニュース おはよう日本\\",\\"path\\":\\"/query/wtkmHz1XU-dOl-so_i2LJlsegL7gV3_laXirRbM5SSM=\\"},{\\"time\\":1768341600,\\"title\\":\\"連続テレビ小説\\",\\"path\\":\\"\\"}]"
      }],
      "code": "OK"
    }
    """

  @Test("Decodes channel programs response")
  func decodesResponse() throws {
    let data = Self.programJSON.data(using: .utf8)!
    let response = try JSONDecoder().decode(ChannelProgramsResponse.self, from: data)

    #expect(response.code == "OK")
    #expect(response.result.count == 1)
    #expect(response.result[0].id == "AA6EC2B2BC19EFE5FA44BE23187CDA63")
  }

  @Test("Parses double-encoded program entries")
  func parsesPrograms() throws {
    let data = Self.programJSON.data(using: .utf8)!
    let response = try JSONDecoder().decode(ChannelProgramsResponse.self, from: data)
    let entries = try response.result[0].parsePrograms()

    #expect(entries.count == 2)

    #expect(entries[0].time == 1768338000)
    #expect(entries[0].title == "NHKニュース おはよう日本")
    #expect(entries[0].path == "/query/wtkmHz1XU-dOl-so_i2LJlsegL7gV3_laXirRbM5SSM=")
    #expect(entries[0].hasVOD == true)

    #expect(entries[1].time == 1768341600)
    #expect(entries[1].title == "連続テレビ小説")
    #expect(entries[1].path == "")
    #expect(entries[1].hasVOD == false)
  }

  @Test("Returns empty array when record_epg is nil")
  func nilProgramHistory() throws {
    let dto = ChannelProgramsDTO(id: "X", name: "Test", programHistory: nil)
    let entries = try dto.parsePrograms()
    #expect(entries.isEmpty)
  }

  @Test("Returns empty array when record_epg is empty string")
  func emptyProgramHistory() throws {
    let dto = ChannelProgramsDTO(id: "X", name: "Test", programHistory: "")
    let entries = try dto.parsePrograms()
    #expect(entries.isEmpty)
  }
}
