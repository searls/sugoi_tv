import SwiftUI

public struct SugoiTVRootView: View {
  var appState: AppState

  public init(appState: AppState) {
    self.appState = appState
  }

  public var body: some View {
    Group {
      if appState.isRestoringSession {
        ProgressView("Restoring session…")
      } else if appState.isAuthenticated {
        AuthenticatedContainer(appState: appState)
      } else {
        #if os(macOS)
        MacSignedOutPlaceholder()
        #else
        LoginView(
          viewModel: LoginViewModel(
            loginAction: { cid, password in
              try await appState.login(cid: cid, password: password)
            }
          )
        )
        #endif
      }
    }
    .task { await appState.restoreSession() }
  }
}

#if os(macOS)
/// Placeholder shown in the main window when not signed in on macOS.
/// Login lives in Settings (⌘,) so the user is directed there.
private struct MacSignedOutPlaceholder: View {
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    ContentUnavailableView {
      Label("Not Signed In", systemImage: "person.crop.circle.badge.questionmark")
    } description: {
      Text("Open Settings to sign in to your YoiTV account.")
    } actions: {
      Button("Open Settings…") {
        openSettings()
      }
      .buttonStyle(.borderedProminent)
      .keyboardShortcut(",", modifiers: .command)
    }
  }
}
#endif

#if DEBUG
#Preview { FixtureContainerPreview() }
#endif
