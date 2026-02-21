import Foundation

/// Raw JSON response from `logon.sjs` and `refresh.sjs`
public struct LoginResponse: Codable, Sendable {
  public let accessToken: String
  public let tokenType: String
  public let expiresIn: Int
  public let refreshToken: String
  public let expired: Bool
  public let disabled: Bool
  public let confirmed: Bool
  public let cid: String
  public let type: String
  public let trial: Int
  public let createTime: Int
  public let expireTime: Int
  public let productConfig: String  // Double-encoded JSON string
  public let serverTime: Int
  public let code: String

  enum CodingKeys: String, CodingKey {
    case accessToken = "access_token"
    case tokenType = "token_type"
    case expiresIn = "expires_in"
    case refreshToken = "refresh_token"
    case expired, disabled, confirmed, cid, type, trial
    case createTime = "create_time"
    case expireTime = "expire_time"
    case productConfig = "product_config"
    case serverTime = "server_time"
    case code
  }
}

/// Parsed `product_config` from within the login response
public struct ProductConfig: Codable, Sendable, Equatable {
  public let vmsHost: String
  public let vmsVodHost: String?
  public let vmsUid: String
  public let vmsLiveCid: String
  public let vmsReferer: String
  public let epgDays: Int?
  public let single: String?

  // Optional override hosts (may not be present in all configs)
  public let vmsChannelListHost: String?
  public let vmsLiveHost: String?
  public let vmsRecordHost: String?
  public let vmsLiveUid: String?

  enum CodingKeys: String, CodingKey {
    case vmsHost = "vms_host"
    case vmsVodHost = "vms_vod_host"
    case vmsUid = "vms_uid"
    case vmsLiveCid = "vms_live_cid"
    case vmsReferer = "vms_referer"
    case epgDays = "epg_days"
    case single
    case vmsChannelListHost = "vms_channel_list_host"
    case vmsLiveHost = "vms_live_host"
    case vmsRecordHost = "vms_record_host"
    case vmsLiveUid = "vms_live_uid"
  }

  /// Dummy config used as a placeholder before authentication provides a real one.
  static let placeholder = ProductConfig(
    vmsHost: "", vmsVodHost: nil, vmsUid: "", vmsLiveCid: "",
    vmsReferer: "", epgDays: nil, single: nil,
    vmsChannelListHost: nil, vmsLiveHost: nil, vmsRecordHost: nil, vmsLiveUid: nil
  )

  // MARK: - Derived host resolution (fallback chain per API spec)

  public var channelListHost: String { vmsChannelListHost ?? vmsHost }
  public var liveHost: String { vmsLiveHost ?? vmsHost }
  public var vodHost: String { vmsVodHost ?? vmsHost }
  public var recordHost: String { vmsRecordHost ?? vmsVodHost ?? vmsHost }
  public var liveUid: String { vmsLiveUid ?? vmsUid }
}

extension LoginResponse {
  /// Parse the double-encoded product_config JSON string
  public func parseProductConfig() throws -> ProductConfig {
    guard let data = productConfig.data(using: .utf8) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: [], debugDescription: "product_config is not valid UTF-8")
      )
    }
    return try JSONDecoder().decode(ProductConfig.self, from: data)
  }
}
