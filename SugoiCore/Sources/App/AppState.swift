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

  /// Attempt to restore a previous session from the Keychain
  public func restoreSession() async {
    isRestoringSession = true
    session = try? await authService.restoreSession()
    if session != nil {
      await authService.startAutoRefresh()
    }
    isRestoringSession = false
  }

  /// Log in with credentials and update session
  public func login(cid: String, password: String) async throws {
    session = try await authService.login(cid: cid, password: password)
    await authService.startAutoRefresh()
  }

  /// Clear session and return to login
  public func logout() async {
    await authService.logout()
    session = nil
  }
}
