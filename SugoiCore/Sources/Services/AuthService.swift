import Foundation

/// Manages authentication lifecycle: login, token refresh, session state
public actor AuthService {
  private let keychain: any KeychainServiceProtocol
  private let apiClient: any APIClientProtocol
  private var refreshTask: Task<Void, Never>?

  /// Current session state, updated on login/refresh/logout
  public private(set) var session: Session?

  public init(
    keychain: any KeychainServiceProtocol,
    apiClient: any APIClientProtocol
  ) {
    self.keychain = keychain
    self.apiClient = apiClient
  }

  // MARK: - Session state

  public struct Session: Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let cid: String
    public let productConfig: ProductConfig
    public let expiresAt: Date
    public let serverTime: Date

    public init(from response: LoginResponse, config: ProductConfig) {
      self.accessToken = response.accessToken
      self.refreshToken = response.refreshToken
      self.cid = response.cid
      self.productConfig = config
      self.expiresAt = Date(timeIntervalSince1970: TimeInterval(response.expiresIn))
      self.serverTime = Date(timeIntervalSince1970: TimeInterval(response.serverTime))
    }
  }

  // MARK: - Login

  public func login(cid: String, password: String) async throws -> Session {
    let deviceID = try await keychain.deviceID()
    let url = YoiTVEndpoints.loginURL(cid: cid, password: password, deviceID: deviceID)
    let response: LoginResponse = try await apiClient.get(url: url)

    guard response.code == "OK" else {
      throw AuthError.loginFailed(code: response.code)
    }
    guard !response.expired && !response.disabled && response.confirmed else {
      throw AuthError.accountInvalid
    }

    let config = try response.parseProductConfig()
    let newSession = Session(from: response, config: config)

    // Persist to Keychain
    try await keychain.storeSession(
      accessToken: response.accessToken,
      refreshToken: response.refreshToken,
      cid: response.cid,
      productConfigJSON: response.productConfig
    )
    try await keychain.storePassword(password)

    self.session = newSession
    return newSession
  }

  // MARK: - Re-authentication with stored credentials

  public func reauthenticateWithStoredCredentials() async throws -> Session {
    guard let cid = try await keychain.cid(),
          let password = try await keychain.password() else {
      throw AuthError.noSession
    }
    return try await login(cid: cid, password: password)
  }

  // MARK: - Token refresh

  public func refreshTokens() async throws -> Session {
    guard let current = session else {
      throw AuthError.noSession
    }

    let deviceID = try await keychain.deviceID()
    let url = YoiTVEndpoints.refreshURL(
      refreshToken: current.refreshToken,
      cid: current.cid,
      deviceID: deviceID
    )
    let response: LoginResponse = try await apiClient.get(url: url)

    if response.code == "AUTH" {
      await logout()
      throw AuthError.sessionExpired
    }
    guard response.code == "OK" else {
      throw AuthError.refreshFailed(code: response.code)
    }

    let config = try response.parseProductConfig()
    let newSession = Session(from: response, config: config)

    try await keychain.storeSession(
      accessToken: response.accessToken,
      refreshToken: response.refreshToken,
      cid: response.cid,
      productConfigJSON: response.productConfig
    )

    self.session = newSession
    return newSession
  }

  // MARK: - Restore session from Keychain

  public func restoreSession() async throws -> Session? {
    guard let accessToken = try await keychain.accessToken(),
          let refreshToken = try await keychain.refreshToken(),
          let cid = try await keychain.cid(),
          let configJSON = try await keychain.productConfigJSON()
    else {
      return nil
    }

    guard let configData = configJSON.data(using: .utf8),
          let config = try? JSONDecoder().decode(ProductConfig.self, from: configData)
    else {
      return nil
    }

    // Return the stored session immediately — don't block on a network
    // refresh. The auto-refresh timer will get fresh tokens in the background.
    let restoredSession = Session(
      accessToken: accessToken,
      refreshToken: refreshToken,
      cid: cid,
      config: config
    )
    self.session = restoredSession
    return restoredSession
  }

  // MARK: - Logout

  public func logout() async {
    stopAutoRefresh()
    session = nil
    try? await keychain.clearSession()
  }

  // MARK: - Auto-refresh

  public func startAutoRefresh(intervalSeconds: TimeInterval = 1800) {
    stopAutoRefresh()
    refreshTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(intervalSeconds))
        guard !Task.isCancelled else { break }
        _ = try? await self?.refreshTokens()
      }
    }
  }

  public func stopAutoRefresh() {
    refreshTask?.cancel()
    refreshTask = nil
  }
}

// MARK: - Session convenience init for restore

extension AuthService.Session {
  init(accessToken: String, refreshToken: String, cid: String, config: ProductConfig) {
    self.accessToken = accessToken
    self.refreshToken = refreshToken
    self.cid = cid
    self.productConfig = config
    self.expiresAt = .distantFuture
    self.serverTime = Date()
  }
}

// MARK: - Errors

public enum AuthError: Error, Sendable, Equatable {
  case loginFailed(code: String)
  case accountInvalid
  case noSession
  case sessionExpired
  case refreshFailed(code: String)
}
