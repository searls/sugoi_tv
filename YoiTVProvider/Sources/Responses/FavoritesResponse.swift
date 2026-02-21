import Foundation

// MARK: - Live Favorites

public struct FavoriteLiveListResponse: Codable, Sendable {
  public let data: [FavoriteLiveDTO]?
  public let max: Int?
  public let code: String
}

public struct FavoriteLiveDTO: Codable, Sendable, Equatable {
  public let vid: String
  public let name: String?
  public let childLock: Int?
  public let sortOrder: Int?
}

public struct FavoriteLiveSyncRequest: Codable, Sendable {
  public let updates: [FavoriteLiveDTO]?
  public let removals: [String]?

  public init(updates: [FavoriteLiveDTO]? = nil, removals: [String]? = nil) {
    self.updates = updates
    self.removals = removals
  }
}

// MARK: - VOD Favorites

public struct FavoriteVodListResponse: Codable, Sendable {
  public let records: [FavoriteVodDTO]?
  public let lastKey: String?
  public let max: Int?
  public let code: String
}

public struct FavoriteVodDTO: Codable, Sendable, Equatable {
  public let vid: String
  public let name: String?
  public let channelId: String?
  public let channelName: String?
  public let childLock: Int?
  public let dupVid: String?
}

public struct FavoriteVodSyncRequest: Codable, Sendable {
  public let updates: [FavoriteVodDTO]?
  public let removals: [String]?

  public init(updates: [FavoriteVodDTO]? = nil, removals: [String]? = nil) {
    self.updates = updates
    self.removals = removals
  }
}
