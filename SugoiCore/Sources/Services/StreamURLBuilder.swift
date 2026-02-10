import AVFoundation
import Foundation

enum StreamURLBuilder {
  /// Build a live HLS stream URL (uppercase .M3U8)
  static func liveURL(session: Session, playpath: String) -> URL? {
    let config = session.productConfig
    let token = session.accessToken.addingPercentEncoding(
      withAllowedCharacters: .urlQueryAllowed
    ) ?? session.accessToken
    return URL(
      string: "\(config.liveHost)\(playpath).M3U8?type=live&__cross_domain_user=\(token)"
    )
  }

  /// Build a VOD/catch-up HLS stream URL (lowercase .m3u8)
  static func vodURL(session: Session, vodPath: String) -> URL? {
    let config = session.productConfig
    let token = session.accessToken.addingPercentEncoding(
      withAllowedCharacters: .urlQueryAllowed
    ) ?? session.accessToken
    return URL(
      string:
        "\(config.recordHost)\(vodPath).m3u8?type=vod&__cross_domain_user=\(token)"
    )
  }

  /// Create an AVURLAsset with the required Referer header
  static func asset(for url: URL, referer: String = "http://play.yoitv.com") -> AVURLAsset {
    AVURLAsset(
      url: url,
      options: ["AVURLAssetHTTPHeaderFieldsKey": ["Referer": referer]]
    )
  }

  /// Platform-appropriate user agent string for single-play enforcement
  static var platformUA: String {
    #if os(iOS)
      return "ios"
    #elseif os(macOS)
      return "macos"
    #elseif os(tvOS)
      return "tvos"
    #else
      return "ios"
    #endif
  }
}
