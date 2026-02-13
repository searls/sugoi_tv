import Foundation
import SwiftUI

/// App-level observable that owns services and drives navigation
@MainActor
@Observable
public final class AppState {
  public let keychain: KeychainService
  public let apiClient: APIClient
  public let authService: AuthService
  public let channelService: ChannelService
  public let epgService: EPGService

  public var session: AuthService.Session?
  public var isRestoringSession: Bool = true

  public init() {
    let keychain = KeychainService()
    let apiClient = APIClient()
    self.keychain = keychain
    self.apiClient = apiClient
    self.authService = AuthService(keychain: keychain, apiClient: apiClient)
    self.channelService = ChannelService(apiClient: apiClient)
    self.epgService = EPGService(apiClient: apiClient)
  }

  /// Testable initializer that accepts pre-built services
  public init(
    keychain: KeychainService = KeychainService(),
    apiClient: APIClient,
    authService: AuthService,
    channelService: ChannelService,
    epgService: EPGService
  ) {
    self.keychain = keychain
    self.apiClient = apiClient
    self.authService = authService
    self.channelService = channelService
    self.epgService = epgService
  }

  /// Attempt to restore a previous session from the Keychain
  public func restoreSession() async {
    isRestoringSession = true
    session = try? await authService.restoreSession()
    if session != nil {
      do {
        session = try await authService.refreshTokens()
        await authService.startAutoRefresh()
      } catch AuthError.sessionExpired {
        // Server revoked the token — logout was already called
        session = nil
      } catch {
        // Network error — keep using stored session with stale tokens
        await authService.startAutoRefresh()
      }
    }
    isRestoringSession = false
  }

  /// Log in with credentials and update session
  public func login(cid: String, password: String) async throws {
    session = try await authService.login(cid: cid, password: password)
    await authService.startAutoRefresh()
  }

  /// Attempt silent re-login using stored credentials.
  /// Returns the new session on success, or nil on auth failure (logout already called).
  /// On transient network errors, returns nil but leaves session and password intact.
  public func reauthenticate() async -> AuthService.Session? {
    do {
      let newSession = try await authService.reauthenticateWithStoredCredentials()
      self.session = newSession
      await authService.startAutoRefresh()
      return newSession
    } catch is AuthError {
      // Definitive auth failure — credentials are bad, clear everything
      await logout()
      return nil
    } catch {
      // Transient network error — leave session and password intact
      return nil
    }
  }

  /// Clear session and return to login
  public func logout() async {
    await authService.logout()
    session = nil
  }
}
