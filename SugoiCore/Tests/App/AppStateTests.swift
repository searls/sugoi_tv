import Foundation
import Testing

@testable import SugoiCore

@Suite("AppState.restoreSession")
@MainActor
struct AppStateRestoreSessionTests {
  @Test("Provider that restores successfully → isAuthenticated true")
  func restoreSuccess() async {
    let mock = MockTVProvider(isAuthenticated: true)
    let appState = AppState(provider: mock)

    await appState.restoreSession()

    #expect(appState.isAuthenticated == true)
    #expect(appState.isRestoringSession == false)
  }

  @Test("Provider that fails restore → isAuthenticated false")
  func restoreFailure() async {
    let mock = MockTVProvider(isAuthenticated: false)
    let appState = AppState(provider: mock)

    await appState.restoreSession()

    #expect(appState.isAuthenticated == false)
    #expect(appState.isRestoringSession == false)
  }

  @Test("isRestoringSession starts true and ends false")
  func restoringSessionLifecycle() async {
    let mock = MockTVProvider(isAuthenticated: false)
    let appState = AppState(provider: mock)

    #expect(appState.isRestoringSession == true)

    await appState.restoreSession()

    #expect(appState.isRestoringSession == false)
  }
}

@Suite("AppState.login")
@MainActor
struct AppStateLoginTests {
  @Test("Successful login sets isAuthenticated")
  func loginSuccess() async throws {
    let mock = MockTVProvider()
    let appState = AppState(provider: mock)

    try await appState.login(credentials: ["cid": "test", "password": "pass"])

    #expect(appState.isAuthenticated == true)
  }

  @Test("Login with credentials dictionary")
  func loginCredentials() async throws {
    let mock = MockTVProvider()
    let appState = AppState(provider: mock)

    try await appState.login(credentials: ["cid": "test", "password": "pass"])

    #expect(appState.isAuthenticated == true)
  }
}

@Suite("AppState.reauthenticate")
@MainActor
struct AppStateReauthenticateTests {
  @Test("Reauthenticate success returns true and sets isAuthenticated")
  func reauthenticateSuccess() async {
    let mock = MockTVProvider(isAuthenticated: true)
    let appState = AppState(provider: mock)

    let result = await appState.reauthenticate()

    #expect(result == true)
    #expect(appState.isAuthenticated == true)
  }

  @Test("Reauthenticate failure returns false and clears isAuthenticated")
  func reauthenticateFailure() async {
    let mock = MockTVProvider(isAuthenticated: false)
    let appState = AppState(provider: mock)

    let result = await appState.reauthenticate()

    #expect(result == false)
    #expect(appState.isAuthenticated == false)
  }
}

@Suite("AppState.logout")
@MainActor
struct AppStateLogoutTests {
  @Test("Logout clears isAuthenticated")
  func logoutClearsAuth() async {
    let mock = MockTVProvider(isAuthenticated: true)
    let appState = AppState(provider: mock)
    // Simulate being authenticated
    try? await appState.login(credentials: ["cid": "x", "password": "x"])
    #expect(appState.isAuthenticated == true)

    await appState.logout()

    #expect(appState.isAuthenticated == false)
  }
}

@Suite("AppState.switchProvider")
@MainActor
struct AppStateSwitchProviderTests {
  init() {
    // Clear persisted provider ID to avoid cross-test contamination
    UserDefaults.standard.removeObject(forKey: "activeProviderID")
  }

  @Test("Switching provider updates activeProvider")
  func switchProvider() async {
    let provider1 = MockTVProvider(displayName: "Provider1", providerID: "p1")
    let provider2 = MockTVProvider(displayName: "Provider2", providerID: "p2", isAuthenticated: true)
    let appState = AppState(providers: [provider1, provider2])

    #expect(appState.activeProvider.providerID == "p1")

    await appState.switchProvider(to: provider2)

    #expect(appState.activeProvider.providerID == "p2")
    #expect(appState.isAuthenticated == true)
  }

  @Test("Switching to provider without session shows unauthenticated")
  func switchToUnauthenticated() async {
    let provider1 = MockTVProvider(displayName: "P1", providerID: "p1", isAuthenticated: true)
    let provider2 = MockTVProvider(displayName: "P2", providerID: "p2", isAuthenticated: false)
    let appState = AppState(providers: [provider1, provider2])

    try? await appState.login(credentials: ["cid": "x", "password": "x"])
    #expect(appState.isAuthenticated == true)

    await appState.switchProvider(to: provider2)

    #expect(appState.isAuthenticated == false)
  }
}
