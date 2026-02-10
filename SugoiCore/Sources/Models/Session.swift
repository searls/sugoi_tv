import Foundation

// MARK: - Product Config (parsed from double-encoded JSON in login response)

struct ProductConfig: Codable, Sendable {
  let vmsHost: String?
  let vmsVodHost: String?
  let vmsUid: String?
  let vmsLiveCid: String?
  let vmsReferer: String?
  let single: String?
  let vmsChannelListHost: String?
  let vmsLiveHost: String?
  let vmsRecordHost: String?
  let vmsLiveUid: String?
  let epgDays: Int?

  enum CodingKeys: String, CodingKey {
    case vmsHost = "vms_host"
    case vmsVodHost = "vms_vod_host"
    case vmsUid = "vms_uid"
    case vmsLiveCid = "vms_live_cid"
    case vmsReferer = "vms_referer"
    case single
    case vmsChannelListHost = "vms_channel_list_host"
    case vmsLiveHost = "vms_live_host"
    case vmsRecordHost = "vms_record_host"
    case vmsLiveUid = "vms_live_uid"
    case epgDays = "epg_days"
  }

  var channelListHost: String { vmsChannelListHost ?? vmsHost ?? "" }
  var liveHost: String { vmsLiveHost ?? vmsHost ?? "" }
  var vodHost: String { vmsVodHost ?? vmsHost ?? "" }
  var recordHost: String { vmsRecordHost ?? vmsVodHost ?? vmsHost ?? "" }
  var liveUid: String { vmsLiveUid ?? vmsUid ?? "" }
  var liveCid: String { vmsLiveCid ?? "" }
  var referer: String { vmsReferer ?? "http://play.yoitv.com" }
  var singlePlayURL: String { single ?? "https://crm.yoitv.com/single.sjs" }
}

// MARK: - Session (stored in Keychain, per-device)

struct Session: Codable, Sendable {
  let accessToken: String
  let refreshToken: String
  let cid: String
  let productConfig: ProductConfig
  let expiresIn: Int
  let serverTime: Int
  let expireTime: Int
}

// MARK: - Credentials (synced via iCloud Keychain)

struct Credentials: Codable, Sendable {
  let cid: String
  let password: String
}
