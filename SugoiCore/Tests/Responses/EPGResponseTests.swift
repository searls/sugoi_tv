import Foundation
import Testing

@testable import SugoiCore

@Suite("EPGResponse")
struct EPGResponseTests {
  static let epgJSON = """
    {
      "result": [{
        "id": "AA6EC2B2BC19EFE5FA44BE23187CDA63",
        "name": "NHK総合・東京",
        "record_epg": "[{\\"time\\":1768338000,\\"title\\":\\"NHKニュース おはよう日本\\",\\"path\\":\\"/query/wtkmHz1XU-dOl-so_i2LJlsegL7gV3_laXirRbM5SSM=\\"},{\\"time\\":1768341600,\\"title\\":\\"連続テレビ小説\\",\\"path\\":\\"\\"}]"
      }],
      "code": "OK"
    }
    """

  @Test("Decodes EPG channel response")
  func decodesResponse() throws {
    let data = Self.epgJSON.data(using: .utf8)!
    let response = try JSONDecoder().decode(EPGChannelResponse.self, from: data)

    #expect(response.code == "OK")
    #expect(response.result.count == 1)
    #expect(response.result[0].id == "AA6EC2B2BC19EFE5FA44BE23187CDA63")
  }

  @Test("Parses double-encoded EPG entries")
  func parsesEPGEntries() throws {
    let data = Self.epgJSON.data(using: .utf8)!
    let response = try JSONDecoder().decode(EPGChannelResponse.self, from: data)
    let entries = try response.result[0].parseEPGEntries()

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
  func nilRecordEpg() throws {
    let dto = EPGChannelDTO(id: "X", name: "Test", recordEpg: nil)
    let entries = try dto.parseEPGEntries()
    #expect(entries.isEmpty)
  }

  @Test("Returns empty array when record_epg is empty string")
  func emptyRecordEpg() throws {
    let dto = EPGChannelDTO(id: "X", name: "Test", recordEpg: "")
    let entries = try dto.parseEPGEntries()
    #expect(entries.isEmpty)
  }
}
