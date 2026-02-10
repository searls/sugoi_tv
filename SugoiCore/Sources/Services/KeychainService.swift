import Foundation
import Security

actor KeychainService {
  static let shared = KeychainService()

  private let service = "com.sugoi.tv"

  // MARK: - Device ID (per-device, NOT synced)

  func deviceId() throws -> String {
    if let existing = try readString(key: "device_id", synced: false) {
      return existing
    }
    let id = (0..<16).map { _ in
      String(format: "%02X", UInt8.random(in: 0...255))
    }.joined()
    try saveString(key: "device_id", value: id, synced: false)
    return id
  }

  // MARK: - Credentials (synced via iCloud Keychain)

  func saveCredentials(_ credentials: Credentials) throws {
    let data = try JSONEncoder().encode(credentials)
    try saveData(key: "credentials", data: data, synced: true)
  }

  func loadCredentials() -> Credentials? {
    guard let data = try? readData(key: "credentials", synced: true) else { return nil }
    return try? JSONDecoder().decode(Credentials.self, from: data)
  }

  func clearCredentials() {
    try? delete(key: "credentials", synced: true)
  }

  // MARK: - Session (per-device, NOT synced)

  func saveSession(_ session: Session) throws {
    let data = try JSONEncoder().encode(session)
    try saveData(key: "session", data: data, synced: false)
  }

  func loadSession() -> Session? {
    guard let data = try? readData(key: "session", synced: false) else { return nil }
    return try? JSONDecoder().decode(Session.self, from: data)
  }

  func clearSession() {
    try? delete(key: "session", synced: false)
  }

  // MARK: - Low-level Keychain operations

  private func saveString(key: String, value: String, synced: Bool) throws {
    guard let data = value.data(using: .utf8) else { return }
    try saveData(key: key, data: data, synced: synced)
  }

  private func readString(key: String, synced: Bool) throws -> String? {
    guard let data = try readData(key: key, synced: synced) else { return nil }
    return String(data: data, encoding: .utf8)
  }

  private func saveData(key: String, data: Data, synced: Bool) throws {
    let query = baseQuery(key: key, synced: synced)
    SecItemDelete(query as CFDictionary)

    var addQuery = query
    addQuery[kSecValueData as String] = data
    let status = SecItemAdd(addQuery as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw KeychainError.saveFailed(status)
    }
  }

  private func readData(key: String, synced: Bool) throws -> Data? {
    var query = baseQuery(key: key, synced: synced)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else {
      throw KeychainError.readFailed(status)
    }
    return result as? Data
  }

  private func delete(key: String, synced: Bool) throws {
    let query = baseQuery(key: key, synced: synced)
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError.deleteFailed(status)
    }
  }

  private func baseQuery(key: String, synced: Bool) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
    ]
    if synced {
      query[kSecAttrSynchronizable as String] = true
    }
    return query
  }
}

enum KeychainError: Error {
  case saveFailed(OSStatus)
  case readFailed(OSStatus)
  case deleteFailed(OSStatus)
}
