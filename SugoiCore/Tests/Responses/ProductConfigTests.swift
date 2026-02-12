import Foundation
import Testing

@testable import SugoiCore

@Suite("ProductConfig host resolution")
struct ProductConfigTests {
  @Test("Falls back to vmsHost when override hosts are nil")
  func fallbackHosts() {
    let config = ProductConfig(
      vmsHost: "http://live.yoitv.com:9083",
      vmsVodHost: nil,
      vmsUid: "UID",
      vmsLiveCid: "CID",
      vmsReferer: "http://play.yoitv.com",
      epgDays: 30,
      single: nil,
      vmsChannelListHost: nil,
      vmsLiveHost: nil,
      vmsRecordHost: nil,
      vmsLiveUid: nil
    )

    #expect(config.channelListHost == "http://live.yoitv.com:9083")
    #expect(config.liveHost == "http://live.yoitv.com:9083")
    #expect(config.vodHost == "http://live.yoitv.com:9083")
    #expect(config.recordHost == "http://live.yoitv.com:9083")
    #expect(config.liveUid == "UID")
  }

  @Test("Uses override hosts when provided")
  func overrideHosts() {
    let config = ProductConfig(
      vmsHost: "http://live.yoitv.com:9083",
      vmsVodHost: "http://vod.yoitv.com:9083",
      vmsUid: "UID",
      vmsLiveCid: "CID",
      vmsReferer: "http://play.yoitv.com",
      epgDays: 30,
      single: nil,
      vmsChannelListHost: "http://channels.yoitv.com:9083",
      vmsLiveHost: "http://live-alt.yoitv.com:9083",
      vmsRecordHost: "http://record.yoitv.com:9083",
      vmsLiveUid: "LIVE_UID"
    )

    #expect(config.channelListHost == "http://channels.yoitv.com:9083")
    #expect(config.liveHost == "http://live-alt.yoitv.com:9083")
    #expect(config.vodHost == "http://vod.yoitv.com:9083")
    #expect(config.recordHost == "http://record.yoitv.com:9083")
    #expect(config.liveUid == "LIVE_UID")
  }

  @Test("recordHost falls back through vmsVodHost then vmsHost")
  func recordHostFallbackChain() {
    let configWithVod = ProductConfig(
      vmsHost: "http://live.yoitv.com:9083",
      vmsVodHost: "http://vod.yoitv.com:9083",
      vmsUid: "UID", vmsLiveCid: "CID", vmsReferer: "ref",
      epgDays: nil, single: nil,
      vmsChannelListHost: nil, vmsLiveHost: nil, vmsRecordHost: nil, vmsLiveUid: nil
    )
    #expect(configWithVod.recordHost == "http://vod.yoitv.com:9083")
  }
}
