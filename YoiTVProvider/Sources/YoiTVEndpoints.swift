import Foundation
import SugoiCore

/// URL builders for YoiTV API endpoints
public enum YoiTVEndpoints {
  /// Login: `GET https://crm.yoitv.com/logon.sjs?...`
  public static func loginURL(cid: String, password: String, deviceID: String) -> URL {
    var components = URLComponents(string: "https://crm.yoitv.com/logon.sjs")!
    components.queryItems = [
      URLQueryItem(name: "from_app", value: "1"),
      URLQueryItem(name: "cid", value: cid),
      URLQueryItem(name: "password", value: password),
      URLQueryItem(name: "app_id", value: ""),
      URLQueryItem(name: "device_id", value: deviceID),
    ]
    return components.url!
  }

  /// Token refresh: `GET https://crm.yoitv.com/refresh.sjs?...`
  public static func refreshURL(refreshToken: String, cid: String, deviceID: String) -> URL {
    var components = URLComponents(string: "https://crm.yoitv.com/refresh.sjs")!
    components.queryItems = [
      URLQueryItem(name: "refresh_token", value: refreshToken),
      URLQueryItem(name: "cid", value: cid),
      URLQueryItem(name: "app_id", value: ""),
      URLQueryItem(name: "device_id", value: deviceID),
    ]
    return components.url!
  }

  /// Channel list: `GET {channelListHost}/api?action=listLives&...`
  public static func channelListURL(config: ProductConfig) -> URL {
    var components = URLComponents(string: "\(config.channelListHost)/api")!
    components.queryItems = [
      URLQueryItem(name: "action", value: "listLives"),
      URLQueryItem(name: "cid", value: config.vmsLiveCid),
      URLQueryItem(name: "uid", value: config.liveUid),
      URLQueryItem(name: "details", value: "0"),
      URLQueryItem(name: "page_size", value: "200"),
      URLQueryItem(name: "sort", value: "no asc"),
      URLQueryItem(name: "sort", value: "created_time desc"),
      URLQueryItem(name: "type", value: "video"),
      URLQueryItem(name: "no_epg", value: "1"),
      URLQueryItem(name: "referer", value: config.vmsReferer),
    ]
    return components.url!
  }

  /// Program guide for a specific channel
  public static func epgURL(config: ProductConfig, channelID: String) -> URL {
    var components = URLComponents(string: "\(config.channelListHost)/api")!
    components.queryItems = [
      URLQueryItem(name: "action", value: "listLives"),
      URLQueryItem(name: "cid", value: config.vmsLiveCid),
      URLQueryItem(name: "uid", value: config.liveUid),
      URLQueryItem(name: "vid", value: channelID),
      URLQueryItem(name: "details", value: "0"),
      URLQueryItem(name: "page_size", value: "200"),
      URLQueryItem(name: "sort", value: "no asc"),
      URLQueryItem(name: "sort", value: "created_time desc"),
      URLQueryItem(name: "type", value: "video"),
      URLQueryItem(name: "no_epg", value: "0"),
      URLQueryItem(name: "epg_days", value: String(config.epgDays ?? 30)),
      URLQueryItem(name: "referer", value: config.vmsReferer),
    ]
    return components.url!
  }

  /// Single-play check: `GET {singleURL}?ua={ua}&own={own}&access_token={token}`
  public static func singlePlayURL(
    singleEndpoint: String,
    ua: String,
    own: Bool,
    accessToken: String
  ) -> URL {
    var components = URLComponents(string: singleEndpoint)!
    components.queryItems = [
      URLQueryItem(name: "ua", value: ua),
      URLQueryItem(name: "own", value: own ? "true" : "false"),
      URLQueryItem(name: "access_token", value: accessToken),
    ]
    return components.url!
  }

  /// CRM user data base URL
  public static func crmURL(controller: String, action: String) -> URL {
    var components = URLComponents(string: "https://crm.yoitv.com/tvum")!
    components.queryItems = [
      URLQueryItem(name: "controller", value: controller),
      URLQueryItem(name: "action", value: action),
    ]
    return components.url!
  }

  /// Bearer auth header for CRM API calls
  public static func bearerHeaders(accessToken: String) -> [String: String] {
    ["Authorization": "Bearer \(accessToken)"]
  }
}
