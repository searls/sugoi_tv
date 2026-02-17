import Foundation

/// Simple file-based cache in the system Caches directory.
/// Suitable for data that can be re-fetched from the network.
enum DiskCache {
  private static let cacheDir: URL = {
    let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("SugoiTV", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }()

  private static func url(for key: String) -> URL {
    cacheDir.appendingPathComponent(key + ".json")
  }

  /// Synchronous read — suitable for init-time cache loading.
  static func load<T: Decodable>(key: String, as type: T.Type) -> T? {
    let fileURL = url(for: key)
    guard let data = try? Data(contentsOf: fileURL) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
  }

  /// One-time migration: removes stale program/channel cache data from UserDefaults.
  /// Safe to call multiple times — becomes a no-op once the sentinel key is set.
  static func migrateFromUserDefaults() {
    let defaults = UserDefaults.standard
    let migrationKey = "diskCacheMigrationDone"
    guard !defaults.bool(forKey: migrationKey) else { return }

    let allKeys = defaults.dictionaryRepresentation().keys
    for key in allKeys where key.hasPrefix("cachedPrograms_") {
      defaults.removeObject(forKey: key)
    }
    defaults.removeObject(forKey: "cachedChannels")
    defaults.set(true, forKey: migrationKey)
  }

  /// Async write — encodes off the main thread, then writes to disk.
  static func save<T: Encodable & Sendable>(key: String, value: T) async {
    let data = await Task.detached {
      try? JSONEncoder().encode(value)
    }.value
    guard let data else { return }
    let fileURL = url(for: key)
    try? data.write(to: fileURL, options: .atomic)
  }
}
