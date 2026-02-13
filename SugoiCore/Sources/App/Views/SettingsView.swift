import SwiftUI

public struct SettingsView: View {
  let appState: AppState

  public init(appState: AppState) {
    self.appState = appState
  }

  public var body: some View {
    Form {
      Section("Account") {
        Button("Sign Out", role: .destructive) {
          Task { await appState.logout() }
        }
        .accessibilityIdentifier("signOutButton")
      }
    }
    .formStyle(.grouped)
    .frame(minWidth: 300, minHeight: 150)
  }
}
