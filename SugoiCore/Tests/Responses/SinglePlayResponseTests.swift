import Foundation
import Testing

@testable import SugoiCore

@Suite("SinglePlayResponse")
struct SinglePlayResponseTests {
  @Test("Decodes single play response - owning")
  func decodesOwning() throws {
    let json = #"{"own": true, "code": "OK"}"#
    let response = try JSONDecoder().decode(SinglePlayResponse.self, from: json.data(using: .utf8)!)
    #expect(response.own == true)
  }

  @Test("Decodes single play response - not owning")
  func decodesNotOwning() throws {
    let json = #"{"own": false, "code": "OK"}"#
    let response = try JSONDecoder().decode(SinglePlayResponse.self, from: json.data(using: .utf8)!)
    #expect(response.own == false)
  }
}
