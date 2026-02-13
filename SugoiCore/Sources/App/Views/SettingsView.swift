import SwiftUI

public struct SettingsView: View {
  let appState: AppState

  public init(appState: AppState) {
    self.appState = appState
  }

  public var body: some View {
    Group {
      if appState.session != nil {
        signedInView
      } else {
        signedOutView
      }
    }
    .frame(minWidth: 350, minHeight: 200)
  }

  private var signedInView: some View {
    Form {
      Section("Account") {
        if let session = appState.session {
          LabeledContent("Customer ID", value: session.cid)
        }
        Button("Sign Out", role: .destructive) {
          Task { await appState.logout() }
        }
        .accessibilityIdentifier("signOutButton")
      }
    }
    .formStyle(.grouped)
  }

  private var signedOutView: some View {
    LoginView(
      viewModel: LoginViewModel(
        loginAction: { cid, password in
          try await appState.login(cid: cid, password: password)
        }
      )
    )
  }
}
