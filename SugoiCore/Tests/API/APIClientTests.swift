import Foundation
import Testing

@testable import SugoiCore

@Suite("APIClient")
struct APIClientTests {
  @Test("GET request decodes JSON response")
  func getRequest() async throws {
    let mock = MockHTTPSession()
    mock.requestHandler = { _ in
      let json = #"{"code":"OK","result":[]}"#
      let response = HTTPURLResponse(
        url: URL(string: "https://example.com")!,
        statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(json.utf8))
    }

    let client = APIClient(session: mock.session)
    let result: ChannelListResponse = try await client.get(url: URL(string: "https://example.com/api")!)
    #expect(result.code == "OK")
    #expect(result.result.isEmpty)
  }

  @Test("GET request throws on HTTP error")
  func getHTTPError() async {
    let mock = MockHTTPSession()
    mock.requestHandler = { _ in
      let response = HTTPURLResponse(
        url: URL(string: "https://example.com")!,
        statusCode: 403, httpVersion: nil, headerFields: nil
      )!
      return (response, Data())
    }

    let client = APIClient(session: mock.session)
    do {
      let _: ChannelListResponse = try await client.get(url: URL(string: "https://example.com")!)
      #expect(Bool(false), "Should have thrown")
    } catch let error as APIError {
      #expect(error == .httpError(statusCode: 403))
    } catch {
      #expect(Bool(false), "Wrong error type: \(error)")
    }
  }

  @Test("POST request sends JSON body and decodes response")
  func postRequest() async throws {
    let mock = MockHTTPSession()
    mock.requestHandler = { request in
      // Verify Content-Type header
      #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
      // Verify Authorization header
      #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer mytoken")
      // Verify body is present
      #expect(request.httpBody != nil || request.httpBodyStream != nil)

      let json = #"{"code":"OK"}"#
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(json.utf8))
    }

    let client = APIClient(session: mock.session)
    let body = FavoriteLiveSyncRequest(updates: nil, removals: ["CH1"])
    let result: FavoriteLiveListResponse = try await client.post(
      url: URL(string: "https://crm.yoitv.com/tvum")!,
      headers: YoiTVEndpoints.bearerHeaders(accessToken: "mytoken"),
      body: body
    )
    #expect(result.code == "OK")
  }
}
