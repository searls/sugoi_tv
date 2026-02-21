import Foundation
import Testing

@testable import YoiTVProvider

@Suite("StreamURLBuilder")
struct StreamURLBuilderTests {
  @Test("Live URL uses uppercase .M3U8")
  func liveURLFormat() {
    let url = StreamURLBuilder.liveStreamURL(
      liveHost: "http://live.yoitv.com:9083",
      playpath: "/query/s/Hqm-m7jqkFlA1CloJoaJZQ==",
      accessToken: "testtoken"
    )
    #expect(url != nil)
    let str = url!.absoluteString
    #expect(str.contains(".M3U8"))
    #expect(str.contains("type=live"))
    #expect(str.contains("__cross_domain_user="))
  }

  @Test("VOD URL uses lowercase .m3u8")
  func vodURLFormat() {
    let url = StreamURLBuilder.vodStreamURL(
      recordHost: "http://vod.yoitv.com:9083",
      path: "/query/wtkmHz1XU-dOl-so_i2LJlsegL7gV3_laXirRbM5SSM=",
      accessToken: "testtoken"
    )
    #expect(url != nil)
    let str = url!.absoluteString
    #expect(str.contains(".m3u8"))
    #expect(!str.contains(".M3U8"))
    #expect(str.contains("type=vod"))
  }

  @Test("Access token with +, /, = is percent-encoded")
  func tokenEncoding() {
    let token = "abc+def/ghi=jkl=="
    let encoded = StreamURLBuilder.percentEncodeToken(token)

    #expect(!encoded.contains("+"))
    #expect(!encoded.contains("/"))
    // = should be encoded
    #expect(encoded.contains("%2B"))  // +
    #expect(encoded.contains("%2F"))  // /
    #expect(encoded.contains("%3D"))  // =
  }

  @Test("Live URL correctly encodes base64 access token")
  func liveURLWithBase64Token() {
    let url = StreamURLBuilder.liveStreamURL(
      liveHost: "http://live.yoitv.com:9083",
      playpath: "/query/s/test",
      accessToken: "ZZVWXJbb+test/token=Krg=="
    )
    let str = url!.absoluteString
    // Token special chars should be percent-encoded
    #expect(!str.contains("+"))  // Should be %2B
    #expect(str.contains("%2B"))
    #expect(str.contains("%2F"))
    #expect(str.contains("%3D"))
  }

  @Test("Favorite VOD URL uses dupVid when available")
  func favoriteVodWithDupVid() {
    let url = StreamURLBuilder.favoriteVodStreamURL(
      vodHost: "http://vod.yoitv.com:9083",
      vid: "originalVid",
      dupVid: "duplicateVid",
      accessToken: "token"
    )
    let str = url!.absoluteString
    #expect(str.contains("/query/duplicateVid.m3u8"))
    #expect(!str.contains("originalVid"))
  }

  @Test("Favorite VOD URL uses vid when dupVid is nil")
  func favoriteVodWithoutDupVid() {
    let url = StreamURLBuilder.favoriteVodStreamURL(
      vodHost: "http://vod.yoitv.com:9083",
      vid: "originalVid",
      dupVid: nil,
      accessToken: "token"
    )
    let str = url!.absoluteString
    #expect(str.contains("/query/originalVid.m3u8"))
  }

  @Test("Thumbnail URL has no auth parameter")
  func thumbnailURL() {
    let url = StreamURLBuilder.thumbnailURL(
      channelListHost: "http://live.yoitv.com:9083",
      playpath: "/query/s/Hqm-m7jqkFlA1CloJoaJZQ=="
    )
    let str = url!.absoluteString
    #expect(str.contains(".jpg"))
    #expect(str.contains("thumbnail=thumbnail_small.jpg"))
    #expect(!str.contains("__cross_domain_user"))
  }

  @Test("Stream URLs use hosts from ProductConfig")
  func usesConfigHosts() {
    let config = ProductConfig(
      vmsHost: "http://live.yoitv.com:9083",
      vmsVodHost: "http://vod.yoitv.com:9083",
      vmsUid: "UID", vmsLiveCid: "CID",
      vmsReferer: "http://play.yoitv.com",
      epgDays: nil, single: nil,
      vmsChannelListHost: nil, vmsLiveHost: "http://live-custom:9083",
      vmsRecordHost: "http://record-custom:9083", vmsLiveUid: nil
    )

    let liveURL = StreamURLBuilder.liveStreamURL(
      liveHost: config.liveHost,
      playpath: "/query/s/test",
      accessToken: "t"
    )
    #expect(liveURL!.absoluteString.hasPrefix("http://live-custom:9083"))

    let vodURL = StreamURLBuilder.vodStreamURL(
      recordHost: config.recordHost,
      path: "/query/test",
      accessToken: "t"
    )
    #expect(vodURL!.absoluteString.hasPrefix("http://record-custom:9083"))
  }
}
