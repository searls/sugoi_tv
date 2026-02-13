import Foundation
import Testing

@testable import SugoiCore

@Suite("KeychainService")
struct KeychainServiceTests {
  @Test("Device ID is 32 hex characters")
  func deviceIDFormat() {
    let id = KeychainService.generateDeviceID()
    #expect(id.count == 32)
    #expect(id.allSatisfy { $0.isHexDigit })
  }

  @Test("Device ID generation produces unique values")
  func deviceIDUniqueness() {
    let ids = (0..<100).map { _ in KeychainService.generateDeviceID() }
    let unique = Set(ids)
    #expect(unique.count == 100)
  }

  @Test("MockKeychainService stores and retrieves session")
  func mockStoresSession() async throws {
    let mock = MockKeychainService()

    try await mock.storeSession(
      accessToken: "token123",
      refreshToken: "refresh456",
      cid: "CID789",
      productConfigJSON: "{}"
    )

    #expect(try await mock.accessToken() == "token123")
    #expect(try await mock.refreshToken() == "refresh456")
    #expect(try await mock.cid() == "CID789")
    #expect(try await mock.productConfigJSON() == "{}")
  }

  @Test("MockKeychainService clearSession removes credentials")
  func mockClearsSession() async throws {
    let mock = MockKeychainService()

    try await mock.storeSession(
      accessToken: "token", refreshToken: "refresh",
      cid: "cid", productConfigJSON: "{}"
    )
    try await mock.clearSession()

    #expect(try await mock.accessToken() == nil)
    #expect(try await mock.refreshToken() == nil)
    #expect(try await mock.cid() == nil)
    #expect(try await mock.productConfigJSON() == nil)
  }

  @Test("MockKeychainService generates and persists device ID")
  func mockDeviceID() async throws {
    let mock = MockKeychainService()
    let id1 = try await mock.deviceID()
    let id2 = try await mock.deviceID()
    #expect(id1 == id2)
    #expect(id1.count == 32)
  }

  @Test("MockKeychainService allows setting deterministic device ID")
  func mockSetDeviceID() async throws {
    let mock = MockKeychainService()
    await mock.setDeviceID("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1")
    let id = try await mock.deviceID()
    #expect(id == "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1")
  }

  @Test("MockKeychainService stores and retrieves password")
  func mockStoresPassword() async throws {
    let mock = MockKeychainService()
    try await mock.storePassword("secret123")
    #expect(try await mock.password() == "secret123")
  }

  @Test("clearSession also clears password")
  func clearRemovesPassword() async throws {
    let mock = MockKeychainService()
    try await mock.storePassword("secret123")
    try await mock.storeSession(
      accessToken: "t", refreshToken: "r", cid: "c", productConfigJSON: "{}"
    )
    try await mock.clearSession()

    #expect(try await mock.password() == nil)
    #expect(try await mock.accessToken() == nil)
  }

  @Test("clearSession does not remove device ID")
  func clearPreservesDeviceID() async throws {
    let mock = MockKeychainService()
    let id = try await mock.deviceID()

    try await mock.storeSession(
      accessToken: "t", refreshToken: "r", cid: "c", productConfigJSON: "{}"
    )
    try await mock.clearSession()

    let idAfterClear = try await mock.deviceID()
    #expect(id == idAfterClear)
  }
}
