import Foundation
import Testing

@testable import SugoiCore

@Suite("MockHTTPSession")
struct MockHTTPSessionTests {
  @Test("Intercepts requests and returns mock response")
  func interceptsRequests() async throws {
    let mock = MockHTTPSession()
    mock.requestHandler = { request in
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200,
        httpVersion: "HTTP/1.1", headerFields: nil
      )!
      return (response, Data("hello".utf8))
    }

    let (data, response) = try await mock.session.data(from: URL(string: "https://example.com/test")!)
    let httpResponse = response as! HTTPURLResponse

    #expect(httpResponse.statusCode == 200)
    #expect(String(data: data, encoding: .utf8) == "hello")
    #expect(mock.capturedRequests.count == 1)
    #expect(mock.capturedRequests[0].url?.absoluteString == "https://example.com/test")
  }

  @Test("MockRouter matches routes by path")
  func routerMatching() async throws {
    let mock = MockHTTPSession()
    var router = MockRouter()
    router.on(pathContaining: "logon.sjs", jsonFixture: #"{"code":"OK"}"#)
    router.on(pathContaining: "listLives", jsonFixture: #"{"result":[],"code":"OK"}"#)
    mock.requestHandler = router.handler()

    let (data1, _) = try await mock.session.data(from: URL(string: "https://crm.yoitv.com/logon.sjs?cid=test")!)
    #expect(String(data: data1, encoding: .utf8)!.contains("OK"))

    let (data2, _) = try await mock.session.data(from: URL(string: "http://live.yoitv.com:9083/api?action=listLives")!)
    #expect(String(data: data2, encoding: .utf8)!.contains("result"))
  }

  @Test("MockRouter throws on unmatched request")
  func routerUnmatched() async {
    let mock = MockHTTPSession()
    let router = MockRouter()
    mock.requestHandler = router.handler()

    do {
      _ = try await mock.session.data(from: URL(string: "https://unknown.com")!)
      #expect(Bool(false), "Should have thrown")
    } catch {
      // Verify we got an error (URLSession may or may not wrap the protocol error)
      let nsError = error as NSError
      #expect(nsError.domain.contains("MockURLProtocolError"))
    }
  }
}
