import Foundation
import SwiftUI

/// App-level observable that owns services and drives navigation
@MainActor
@Observable
public final class AppState {
  /// The currently active TV provider.
  public private(set) var activeProvider: any TVProvider

  /// All registered providers.
  public let availableProviders: [any TVProvider]

  /// Whether the app is still restoring a session on launch.
  public var isRestoringSession: Bool = true

  /// Whether the active provider has an authenticated session.
  /// Observable wrapper around provider.isAuthenticated for SwiftUI reactivity.
  public private(set) var isAuthenticated: Bool = false

  /// Provider-specific account identifier (e.g. CID for YoiTV), shown in settings.
  public private(set) var accountID: String?

  /// Referer string for the proxy (YoiTV-specific, nil for providers that don't need it).
  public private(set) var vmsReferer: String?

  public init(providers: [any TVProvider]) {
    DiskCache.migrateFromUserDefaults()
    precondition(!providers.isEmpty, "At least one provider is required")

    self.availableProviders = providers

    // Restore last-used provider or default to first
    let lastID = UserDefaults.standard.string(forKey: "activeProviderID")
    self.activeProvider = providers.first { $0.providerID == lastID } ?? providers[0]
  }

  /// Testable initializer with a single provider.
  public init(provider: any TVProvider) {
    self.availableProviders = [provider]
    self.activeProvider = provider
  }

  // MARK: - Session lifecycle

  /// Attempt to restore a previous session from persistent storage.
  public func restoreSession() async {
    isRestoringSession = true
    let restored = (try? await activeProvider.restoreSession()) ?? false
    isAuthenticated = restored
    syncProviderState()
    isRestoringSession = false

    if restored {
      await activeProvider.startAutoRefresh()
    }
  }

  /// Log in with credentials.
  public func login(credentials: [String: String]) async throws {
    try await activeProvider.login(credentials: credentials)
    isAuthenticated = true
    syncProviderState()
    await activeProvider.startAutoRefresh()
  }

  /// Convenience for the two-field YoiTV login form.
  public func login(cid: String, password: String) async throws {
    try await login(credentials: ["cid": cid, "password": password])
  }

  /// Attempt silent re-authentication using stored credentials.
  /// Returns true on success, false on failure.
  public func reauthenticate() async -> Bool {
    do {
      let success = try await activeProvider.reauthenticate()
      if success {
        isAuthenticated = true
        syncProviderState()
        return true
      } else {
        isAuthenticated = false
        syncProviderState()
        return false
      }
    } catch {
      // Transient failure — leave state unchanged
      return false
    }
  }

  /// Clear session and return to login.
  public func logout() async {
    await activeProvider.logout()
    isAuthenticated = false
    syncProviderState()
  }

  // MARK: - Provider switching

  /// Switch to a different provider. Stops playback and attempts session restore.
  public func switchProvider(to provider: any TVProvider) async {
    await activeProvider.stopPlaybackEnforcement()
    activeProvider = provider
    UserDefaults.standard.set(provider.providerID, forKey: "activeProviderID")
    isAuthenticated = false
    syncProviderState()

    let restored = (try? await provider.restoreSession()) ?? false
    isAuthenticated = restored
    syncProviderState()
  }

  // MARK: - Preview support

  #if DEBUG
  /// Set authenticated state for SwiftUI previews (bypasses provider auth flow).
  public func setAuthenticatedForPreview() {
    isAuthenticated = true
    isRestoringSession = false
  }
  #endif

  // MARK: - Internal

  /// Sync provider-specific state into observable properties.
  private func syncProviderState() {
    if let yoitv = activeProvider as? YoiTVProviderAdapter {
      accountID = yoitv.cid
      vmsReferer = yoitv.vmsReferer
    } else {
      accountID = nil
      vmsReferer = nil
    }
  }
}
