import Foundation
import Security

// MARK: - Protocol for testability

public protocol KeychainServiceProtocol: Sendable {
  func deviceID() async throws -> String
  func storeSession(
    accessToken: String, refreshToken: String, cid: String, productConfigJSON: String
  ) async throws
  func accessToken() async throws -> String?
  func refreshToken() async throws -> String?
  func cid() async throws -> String?
  func productConfigJSON() async throws -> String?
  func clearSession() async throws
}

// MARK: - Errors

public enum KeychainError: Error, Sendable {
  case unexpectedStatus(OSStatus)
  case dataConversionFailed
  case itemNotFound
}

// MARK: - Implementation

public actor KeychainService: KeychainServiceProtocol {
  private let serviceName: String
  private let accessGroup: String?
  private let synchronizable: Bool

  public init(
    serviceName: String = "com.searls.sugoi-tv",
    accessGroup: String? = nil,
    synchronizable: Bool = true  // iCloud Keychain sync
  ) {
    self.serviceName = serviceName
    self.accessGroup = accessGroup
    self.synchronizable = synchronizable
  }

  // MARK: - Device ID

  private static let deviceIDKey = "device_id"

  public func deviceID() async throws -> String {
    if let existing = try? getString(forKey: Self.deviceIDKey) {
      return existing
    }
    let newID = Self.generateDeviceID()
    try setString(newID, forKey: Self.deviceIDKey)
    return newID
  }

  /// Generate a 32-character uppercase hex string from 16 random bytes
  static func generateDeviceID() -> String {
    (0..<16).map { _ in String(format: "%02X", UInt8.random(in: 0...255)) }.joined()
  }

  // MARK: - Session credentials

  private static let accessTokenKey = "access_token"
  private static let refreshTokenKey = "refresh_token"
  private static let cidKey = "cid"
  private static let productConfigKey = "product_config"

  public func storeSession(
    accessToken: String, refreshToken: String, cid: String, productConfigJSON: String
  ) async throws {
    try setString(accessToken, forKey: Self.accessTokenKey)
    try setString(refreshToken, forKey: Self.refreshTokenKey)
    try setString(cid, forKey: Self.cidKey)
    try setString(productConfigJSON, forKey: Self.productConfigKey)
  }

  public func accessToken() async throws -> String? {
    try? getString(forKey: Self.accessTokenKey)
  }

  public func refreshToken() async throws -> String? {
    try? getString(forKey: Self.refreshTokenKey)
  }

  public func cid() async throws -> String? {
    try? getString(forKey: Self.cidKey)
  }

  public func productConfigJSON() async throws -> String? {
    try? getString(forKey: Self.productConfigKey)
  }

  public func clearSession() async throws {
    for key in [Self.accessTokenKey, Self.refreshTokenKey, Self.cidKey, Self.productConfigKey] {
      try? deleteItem(forKey: key)
    }
  }

  // MARK: - Low-level Keychain operations

  private func baseQuery(forKey key: String) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: serviceName,
      kSecAttrAccount as String: key,
    ]
    if synchronizable {
      query[kSecAttrSynchronizable as String] = kCFBooleanTrue
    }
    if let group = accessGroup {
      query[kSecAttrAccessGroup as String] = group
    }
    return query
  }

  private func getString(forKey key: String) throws -> String {
    var query = baseQuery(forKey: key)
    query[kSecReturnData as String] = kCFBooleanTrue
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status != errSecItemNotFound else { throw KeychainError.itemNotFound }
    guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    guard let data = result as? Data, let string = String(data: data, encoding: .utf8) else {
      throw KeychainError.dataConversionFailed
    }
    return string
  }

  private func setString(_ value: String, forKey key: String) throws {
    guard let data = value.data(using: .utf8) else {
      throw KeychainError.dataConversionFailed
    }

    // Try to update existing item first
    let query = baseQuery(forKey: key)
    let attributes: [String: Any] = [kSecValueData as String: data]
    let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

    if updateStatus == errSecItemNotFound {
      // Item doesn't exist, add it
      var addQuery = query
      addQuery[kSecValueData as String] = data
      let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
      guard addStatus == errSecSuccess else {
        throw KeychainError.unexpectedStatus(addStatus)
      }
    } else if updateStatus != errSecSuccess {
      throw KeychainError.unexpectedStatus(updateStatus)
    }
  }

  private func deleteItem(forKey key: String) throws {
    let query = baseQuery(forKey: key)
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError.unexpectedStatus(status)
    }
  }
}

// MARK: - Mock for testing

public actor MockKeychainService: KeychainServiceProtocol {
  private var store: [String: String] = [:]
  private var generatedDeviceID: String?

  public init() {}

  public func deviceID() async throws -> String {
    if let id = store["device_id"] {
      return id
    }
    let id = generatedDeviceID ?? KeychainService.generateDeviceID()
    store["device_id"] = id
    return id
  }

  /// Set a specific device ID for deterministic testing
  public func setDeviceID(_ id: String) {
    store["device_id"] = id
  }

  public func storeSession(
    accessToken: String, refreshToken: String, cid: String, productConfigJSON: String
  ) async throws {
    store["access_token"] = accessToken
    store["refresh_token"] = refreshToken
    store["cid"] = cid
    store["product_config"] = productConfigJSON
  }

  public func accessToken() async throws -> String? { store["access_token"] }
  public func refreshToken() async throws -> String? { store["refresh_token"] }
  public func cid() async throws -> String? { store["cid"] }
  public func productConfigJSON() async throws -> String? { store["product_config"] }

  public func clearSession() async throws {
    store.removeValue(forKey: "access_token")
    store.removeValue(forKey: "refresh_token")
    store.removeValue(forKey: "cid")
    store.removeValue(forKey: "product_config")
  }
}
