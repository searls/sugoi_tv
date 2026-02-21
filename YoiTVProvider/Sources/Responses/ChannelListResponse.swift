import Foundation
import SugoiCore

/// Response from `listLives` with `no_epg=1`
public struct ChannelListResponse: Codable, Sendable {
  public let result: [ChannelDTO]
  public let code: String
}
