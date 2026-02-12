import Foundation
import Testing

@testable import SugoiCore

@Suite("SinglePlayService")
struct SinglePlayServiceTests {
  @Test("Check ownership returns true when API returns own=true")
  func checkOwnershipTrue() async throws {
    let mock = MockHTTPSession()
    mock.requestHandler = { request in
      #expect(request.url!.absoluteString.contains("single.sjs"))
      #expect(request.url!.absoluteString.contains("own=true"))
      #expect(request.url!.absoluteString.contains("ua=ios"))
      let json = #"{"own": true, "code": "OK"}"#
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(json.utf8))
    }

    let service = SinglePlayService(apiClient: APIClient(session: mock.session))
    let owns = try await service.checkOwnership(
      singleEndpoint: "https://crm.yoitv.com/single.sjs",
      accessToken: "token123",
      ua: "ios",
      own: true
    )

    #expect(owns == true)
    #expect(await service.isOwning == true)
  }

  @Test("Check ownership returns false when another session is active")
  func checkOwnershipFalse() async throws {
    let mock = MockHTTPSession()
    mock.requestHandler = { request in
      let json = #"{"own": false, "code": "OK"}"#
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(json.utf8))
    }

    let service = SinglePlayService(apiClient: APIClient(session: mock.session))
    let owns = try await service.checkOwnership(
      singleEndpoint: "https://crm.yoitv.com/single.sjs",
      accessToken: "token123",
      ua: "ios",
      own: true
    )

    #expect(owns == false)
    #expect(await service.isOwning == false)
  }

  @Test("Stop polling resets ownership state")
  func stopPollingResetsState() async throws {
    let mock = MockHTTPSession()
    mock.requestHandler = { request in
      let json = #"{"own": true, "code": "OK"}"#
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(json.utf8))
    }

    let service = SinglePlayService(apiClient: APIClient(session: mock.session))
    _ = try await service.checkOwnership(
      singleEndpoint: "https://crm.yoitv.com/single.sjs",
      accessToken: "t", ua: "ios", own: true
    )
    #expect(await service.isOwning == true)

    await service.stopPolling()
    #expect(await service.isOwning == false)
  }

  @Test("Platform UA returns expected value")
  func platformUA() {
    let ua = SinglePlayService.platformUA
    #if os(iOS)
    #expect(ua == "ios")
    #elseif os(macOS)
    #expect(ua == "macos")
    #elseif os(tvOS)
    #expect(ua == "tvos")
    #endif
  }
}
