import Foundation
import Testing

@testable import SugoiCore

@Suite("YoiTVEndpoints")
struct YoiTVEndpointsTests {
  @Test("Login URL contains all required parameters")
  func loginURL() {
    let url = YoiTVEndpoints.loginURL(cid: "AABC538835997", password: "testpass", deviceID: "AABB1122")
    let str = url.absoluteString

    #expect(str.contains("crm.yoitv.com/logon.sjs"))
    #expect(str.contains("from_app=1"))
    #expect(str.contains("cid=AABC538835997"))
    #expect(str.contains("password=testpass"))
    #expect(str.contains("app_id="))
    #expect(str.contains("device_id=AABB1122"))
  }

  @Test("Refresh URL contains all required parameters")
  func refreshURL() {
    let url = YoiTVEndpoints.refreshURL(refreshToken: "refresh123", cid: "CID1", deviceID: "DEV1")
    let str = url.absoluteString

    #expect(str.contains("crm.yoitv.com/refresh.sjs"))
    #expect(str.contains("refresh_token=refresh123"))
    #expect(str.contains("cid=CID1"))
    #expect(str.contains("device_id=DEV1"))
  }

  @Test("Channel list URL uses config hosts")
  func channelListURL() {
    let config = ProductConfig(
      vmsHost: "http://live.yoitv.com:9083",
      vmsVodHost: nil, vmsUid: "UID1", vmsLiveCid: "CID1",
      vmsReferer: "http://play.yoitv.com", epgDays: 30, single: nil,
      vmsChannelListHost: nil, vmsLiveHost: nil, vmsRecordHost: nil, vmsLiveUid: nil
    )
    let url = YoiTVEndpoints.channelListURL(config: config)
    let str = url.absoluteString

    #expect(str.hasPrefix("http://live.yoitv.com:9083/api"))
    #expect(str.contains("action=listLives"))
    #expect(str.contains("cid=CID1"))
    #expect(str.contains("uid=UID1"))
    #expect(str.contains("no_epg=1"))
    #expect(str.contains("page_size=200"))
  }

  @Test("Program guide URL includes channel ID and no_epg=0")
  func programGuideURL() {
    let config = ProductConfig(
      vmsHost: "http://live.yoitv.com:9083",
      vmsVodHost: nil, vmsUid: "UID1", vmsLiveCid: "CID1",
      vmsReferer: "http://play.yoitv.com", epgDays: 30, single: nil,
      vmsChannelListHost: nil, vmsLiveHost: nil, vmsRecordHost: nil, vmsLiveUid: nil
    )
    let url = YoiTVEndpoints.epgURL(config: config, channelID: "CHAN123")
    let str = url.absoluteString

    #expect(str.contains("vid=CHAN123"))
    #expect(str.contains("no_epg=0"))
    #expect(str.contains("epg_days=30"))
  }

  @Test("Single play URL formats correctly")
  func singlePlayURL() {
    let url = YoiTVEndpoints.singlePlayURL(
      singleEndpoint: "https://crm.yoitv.com/single.sjs",
      ua: "ios", own: true, accessToken: "token123"
    )
    let str = url.absoluteString

    #expect(str.contains("single.sjs"))
    #expect(str.contains("ua=ios"))
    #expect(str.contains("own=true"))
    #expect(str.contains("access_token=token123"))
  }

  @Test("Bearer headers format correctly")
  func bearerHeaders() {
    let headers = YoiTVEndpoints.bearerHeaders(accessToken: "mytoken")
    #expect(headers["Authorization"] == "Bearer mytoken")
  }

  @Test("CRM URL builds with controller and action")
  func crmURL() {
    let url = YoiTVEndpoints.crmURL(controller: "tvum_favorite", action: "listLive")
    let str = url.absoluteString
    #expect(str.contains("crm.yoitv.com/tvum"))
    #expect(str.contains("controller=tvum_favorite"))
    #expect(str.contains("action=listLive"))
  }
}
