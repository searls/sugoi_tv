import Foundation

// MARK: - Login / Refresh

struct LoginResponse: Codable, Sendable {
  let accessToken: String?
  let refreshToken: String?
  let cid: String?
  let productConfig: String?  // Double-encoded JSON string
  let expiresIn: Int?
  let serverTime: Int?
  let expireTime: Int?
  let code: String
  let expired: Bool?
  let disabled: Bool?
  let confirmed: Bool?

  enum CodingKeys: String, CodingKey {
    case accessToken = "access_token"
    case refreshToken = "refresh_token"
    case cid
    case productConfig = "product_config"
    case expiresIn = "expires_in"
    case serverTime = "server_time"
    case expireTime = "expire_time"
    case code, expired, disabled, confirmed
  }
}

// MARK: - Channel List

struct ChannelListResponse: Codable, Sendable {
  let result: [ChannelResult]?
  let code: String
}

struct ChannelResult: Codable, Sendable {
  let id: String
  let name: String
  let description: String?
  let tags: String?
  let playpath: String?
  let no: Int?
  let running: Int?
  let timeshift: Int?
  let epgKeepDays: Int?
  let recordEpg: String?  // Double-encoded JSON string

  enum CodingKeys: String, CodingKey {
    case id, name, description, tags, playpath, no, running, timeshift
    case epgKeepDays = "epg_keep_days"
    case recordEpg = "record_epg"
  }
}

// MARK: - EPG

struct EPGResult: Codable, Sendable {
  let time: Int
  let title: String
  let path: String
}

// MARK: - Single Play

struct SinglePlayResponse: Codable, Sendable {
  let own: Bool?
  let code: String?
}

// MARK: - Play Records

struct PlayRecordListResponse: Codable, Sendable {
  let code: String
  let data: [PlayRecordResult]?
}

struct PlayRecordResult: Codable, Sendable {
  let vid: String
  let name: String
  let duration: Int?
  let pos: Int?
  let channelId: String?
  let channelName: String?
  let playAt: Int?
}

// MARK: - Sync Payloads

struct SyncPlayRecordPayload: Codable, Sendable {
  let updates: [SyncPlayRecordEntry]
}

struct SyncPlayRecordEntry: Codable, Sendable {
  let vid: String
  let name: String
  let duration: Int
  let pos: Int
  let ended: Bool
  let channelId: String
  let channelName: String
}
