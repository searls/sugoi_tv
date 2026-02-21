import Foundation
import Testing

@testable import YoiTVProvider

@Suite("FavoritesResponse")
struct FavoritesResponseTests {
  @Test("Decodes live favorites list")
  func decodesLiveFavorites() throws {
    let json = """
      {"data": [{"vid": "CH1", "name": "NHK", "childLock": 0, "sortOrder": 1}], "max": 300, "code": "OK"}
      """
    let response = try JSONDecoder().decode(FavoriteLiveListResponse.self, from: json.data(using: .utf8)!)
    #expect(response.code == "OK")
    #expect(response.data?.count == 1)
    #expect(response.data?[0].vid == "CH1")
    #expect(response.max == 300)
  }

  @Test("Decodes VOD favorites list")
  func decodesVodFavorites() throws {
    let json = """
      {"records": [{"vid": "V1", "name": "Show", "channelId": "C1", "channelName": "NHK", "childLock": 0, "dupVid": "DV1"}], "lastKey": null, "max": 1000, "code": "OK"}
      """
    let response = try JSONDecoder().decode(FavoriteVodListResponse.self, from: json.data(using: .utf8)!)
    #expect(response.code == "OK")
    #expect(response.records?.count == 1)
    #expect(response.records?[0].dupVid == "DV1")
  }
}
