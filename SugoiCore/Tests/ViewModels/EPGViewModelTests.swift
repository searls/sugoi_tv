import Foundation
import Testing

@testable import SugoiCore

@Suite("EPGViewModel")
struct EPGViewModelTests {
  static var testConfig: ProductConfig {
    ProductConfig(
      vmsHost: "http://live.yoitv.com:9083",
      vmsVodHost: nil, vmsUid: "UID", vmsLiveCid: "CID",
      vmsReferer: "http://play.yoitv.com", epgDays: 30, single: nil,
      vmsChannelListHost: nil, vmsLiveHost: nil, vmsRecordHost: nil, vmsLiveUid: nil
    )
  }

  @Test("Loads EPG entries successfully")
  @MainActor
  func loadEPG() async {
    let mock = MockHTTPSession()
    let epgJSON = """
      {
        "result": [{
          "id": "CH1",
          "name": "NHK",
          "record_epg": "[{\\"time\\":1000,\\"title\\":\\"Morning Show\\",\\"path\\":\\"/query/morning\\"},{\\"time\\":2000,\\"title\\":\\"Afternoon Show\\",\\"path\\":\\"\\"},{\\"time\\":9999999999,\\"title\\":\\"Future Show\\",\\"path\\":\\"\\"}]"
        }],
        "code": "OK"
      }
      """
    mock.requestHandler = { _ in
      let response = HTTPURLResponse(
        url: URL(string: "http://test.com")!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(epgJSON.utf8))
    }

    let service = EPGService(apiClient: APIClient(session: mock.session))
    let vm = EPGViewModel(
      epgService: service, config: Self.testConfig,
      channelID: "CH1", channelName: "NHK"
    )

    await vm.loadEPG()

    #expect(vm.isLoading == false)
    #expect(vm.errorMessage == nil)
    #expect(vm.entries.count == 3)
    #expect(vm.channelName == "NHK")
  }

  @Test("Current program is detected")
  @MainActor
  func currentProgram() async {
    let mock = MockHTTPSession()
    let json = """
      {
        "result": [{
          "id": "CH1",
          "name": "NHK",
          "record_epg": "[{\\"time\\":1000,\\"title\\":\\"Past Show\\",\\"path\\":\\"/past\\"},{\\"time\\":\(Int(Date().timeIntervalSince1970) - 100),\\"title\\":\\"Current Show\\",\\"path\\":\\"\\"},{\\"time\\":\(Int(Date().timeIntervalSince1970) + 3600),\\"title\\":\\"Future Show\\",\\"path\\":\\"\\"}]"
        }],
        "code": "OK"
      }
      """
    mock.requestHandler = { _ in
      let response = HTTPURLResponse(
        url: URL(string: "http://test.com")!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(json.utf8))
    }

    let service = EPGService(apiClient: APIClient(session: mock.session))
    let vm = EPGViewModel(
      epgService: service, config: Self.testConfig,
      channelID: "CH1", channelName: "NHK"
    )

    await vm.loadEPG()

    #expect(vm.currentProgram != nil)
    #expect(vm.currentProgram?.title == "Current Show")
  }

  @Test("Load failure sets error message")
  @MainActor
  func loadFailure() async {
    let mock = MockHTTPSession()
    mock.requestHandler = { _ in
      throw URLError(.notConnectedToInternet)
    }

    let service = EPGService(apiClient: APIClient(session: mock.session))
    let vm = EPGViewModel(
      epgService: service, config: Self.testConfig,
      channelID: "CH1", channelName: "NHK"
    )

    await vm.loadEPG()

    #expect(vm.isLoading == false)
    #expect(vm.errorMessage == "Failed to load program guide.")
    #expect(vm.entries.isEmpty)
  }
}
