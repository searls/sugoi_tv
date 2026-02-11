import Foundation
import Observation

@Observable @MainActor
final class AuthManager {
  enum AuthState {
    case unknown
    case loggedOut
    case loggedIn(Session)
  }

  private(set) var state: AuthState = .unknown
  private(set) var isLoading = false
  var errorMessage: String?

  private let keychain = KeychainService.shared
  private let api = APIClient.shared
  private var refreshTask: Task<Void, Never>?

  var session: Session? {
    if case .loggedIn(let session) = state { return session }
    return nil
  }

  // MARK: - Initialize (app startup)

  func initialize() async {
    // Try to restore an existing session
    if let stored = await keychain.loadSession() {
      // Try refreshing the token
      do {
        let refreshed = try await refreshSession(stored)
        state = .loggedIn(refreshed)
        startRefreshTimer()
        return
      } catch {
        // Refresh failed — try re-login with stored credentials
        await keychain.clearSession()
      }
    }

    // Try auto-login with iCloud Keychain credentials
    if let creds = await keychain.loadCredentials() {
      do {
        try await login(cid: creds.cid, password: creds.password)
        return
      } catch {
        // Stored credentials are stale
      }
    }

    #if DEBUG
      // Auto-login from environment variables (for simulator testing)
      let env = ProcessInfo.processInfo.environment
      if let envCid = env["YOITV_USER"],
        let envPass = env["YOITV_PASS"]
      {
        do {
          try await login(cid: envCid, password: envPass)
          return
        } catch {
          // Fall through to show login screen
        }
      }
    #endif

    state = .loggedOut
  }

  // MARK: - Login

  func login(cid: String, password: String) async throws {
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }

    let deviceId = try await keychain.deviceId()
    let response = try await api.login(cid: cid, password: password, deviceId: deviceId)

    let session = try parseLoginResponse(response)

    // Persist session (device-local) and credentials (iCloud synced)
    try await keychain.saveSession(session)
    try await keychain.saveCredentials(Credentials(cid: cid, password: password))

    state = .loggedIn(session)
    startRefreshTimer()
  }

  // MARK: - Refresh Timer (every 30 minutes)

  private func startRefreshTimer() {
    refreshTask?.cancel()
    refreshTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1800))
        guard !Task.isCancelled else { break }
        await self?.refreshIfNeeded()
      }
    }
  }

  private func stopRefreshTimer() {
    refreshTask?.cancel()
    refreshTask = nil
  }

  func refreshIfNeeded() async {
    guard let current = session else { return }
    do {
      let refreshed = try await refreshSession(current)
      state = .loggedIn(refreshed)
    } catch {
      await logout()
    }
  }

  private func refreshSession(_ current: Session) async throws -> Session {
    let deviceId = try await keychain.deviceId()
    let response = try await api.refresh(
      refreshToken: current.refreshToken,
      cid: current.cid,
      deviceId: deviceId
    )

    if response.code == "AUTH" {
      throw AuthError.invalidCredentials
    }

    let session = try parseLoginResponse(response)
    try await keychain.saveSession(session)
    return session
  }

  // MARK: - Logout

  func logout() async {
    stopRefreshTimer()
    await keychain.clearSession()
    state = .loggedOut
  }

  // MARK: - Parse login/refresh response

  private func parseLoginResponse(_ response: LoginResponse) throws -> Session {
    guard response.code == "OK" else {
      if response.expired == true { throw AuthError.accountExpired }
      if response.disabled == true { throw AuthError.accountDisabled }
      throw AuthError.serverError(response.code)
    }

    guard let accessToken = response.accessToken,
      let refreshToken = response.refreshToken,
      let cid = response.cid,
      let configString = response.productConfig,
      let expiresIn = response.expiresIn,
      let serverTime = response.serverTime,
      let expireTime = response.expireTime
    else {
      throw AuthError.missingFields
    }

    // Double-decode product_config (it's a JSON string inside JSON)
    guard let configData = configString.data(using: .utf8) else {
      throw AuthError.missingFields
    }
    let productConfig = try JSONDecoder().decode(ProductConfig.self, from: configData)

    return Session(
      accessToken: accessToken,
      refreshToken: refreshToken,
      cid: cid,
      productConfig: productConfig,
      expiresIn: expiresIn,
      serverTime: serverTime,
      expireTime: expireTime
    )
  }
}
