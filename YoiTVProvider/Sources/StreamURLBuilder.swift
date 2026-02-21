import Foundation

/// Builds HLS streaming URLs for live and VOD content
public enum StreamURLBuilder {

  /// Live stream HLS URL (uppercase .M3U8)
  /// Pattern: `{liveHost}{playpath}.M3U8?type=live&__cross_domain_user={urlEncodedToken}`
  public static func liveStreamURL(
    liveHost: String,
    playpath: String,
    accessToken: String
  ) -> URL? {
    let encoded = percentEncodeToken(accessToken)
    return URL(string: "\(liveHost)\(playpath).M3U8?type=live&__cross_domain_user=\(encoded)")
  }

  /// VOD/recorded program HLS URL (lowercase .m3u8)
  /// Pattern: `{recordHost}{path}.m3u8?type=vod&__cross_domain_user={urlEncodedToken}`
  public static func vodStreamURL(
    recordHost: String,
    path: String,
    accessToken: String
  ) -> URL? {
    let encoded = percentEncodeToken(accessToken)
    return URL(string: "\(recordHost)\(path).m3u8?type=vod&__cross_domain_user=\(encoded)")
  }

  /// Favorite VOD playback URL
  /// Pattern: `{vodHost}/query/{vid}.m3u8?type=vod&__cross_domain_user={token}`
  /// Uses `dupVid` if available, otherwise `vid`
  public static func favoriteVodStreamURL(
    vodHost: String,
    vid: String,
    dupVid: String?,
    accessToken: String
  ) -> URL? {
    let effectiveVid = dupVid ?? vid
    let encoded = percentEncodeToken(accessToken)
    return URL(string: "\(vodHost)/query/\(effectiveVid).m3u8?type=vod&__cross_domain_user=\(encoded)")
  }

  /// Channel thumbnail URL (no auth required)
  /// Pattern: `{channelListHost}{playpath}.jpg?type=live&thumbnail=thumbnail_small.jpg`
  public static func thumbnailURL(
    channelListHost: String,
    playpath: String
  ) -> URL? {
    URL(string: "\(channelListHost)\(playpath).jpg?type=live&thumbnail=thumbnail_small.jpg")
  }

  /// Referer header value required for all stream requests
  public static func refererHeader(from config: ProductConfig) -> [String: String] {
    ["Referer": config.vmsReferer]
  }

  // MARK: - Token encoding

  /// Percent-encode an access token for use in URL query parameters.
  /// Base64 tokens contain `+`, `/`, and `=` which must be encoded.
  static func percentEncodeToken(_ token: String) -> String {
    var allowed = CharacterSet.urlQueryAllowed
    // These are technically allowed in query strings but must be encoded
    // for this API's __cross_domain_user parameter
    allowed.remove(charactersIn: "+/=")
    return token.addingPercentEncoding(withAllowedCharacters: allowed) ?? token
  }
}
