import SwiftUI

public struct SettingsView: View {
  let appState: AppState
  @State private var selectedProviderID: String

  public init(appState: AppState) {
    self.appState = appState
    self._selectedProviderID = State(initialValue: appState.activeProvider.providerID)
  }

  public var body: some View {
    Group {
      if appState.isAuthenticated {
        signedInView
      } else {
        signedOutView
      }
    }
    .frame(minWidth: 350, minHeight: 200)
  }

  private var signedInView: some View {
    Form {
      if appState.availableProviders.count > 1 {
        Section("Service") {
          Picker("Provider", selection: $selectedProviderID) {
            ForEach(appState.availableProviders, id: \.providerID) { provider in
              Text(provider.displayName).tag(provider.providerID)
            }
          }
        }
      }
      Section("Account") {
        if let accountID = appState.accountID {
          LabeledContent("Account", value: accountID)
        }
        Button("Sign Out", role: .destructive) {
          Task { await appState.logout() }
        }
        .accessibilityIdentifier("signOutButton")
      }
    }
    .formStyle(.grouped)
    .onChange(of: selectedProviderID) { _, newID in
      guard newID != appState.activeProvider.providerID,
            let provider = appState.availableProviders.first(where: { $0.providerID == newID })
      else { return }
      Task { await appState.switchProvider(to: provider) }
    }
  }

  private var signedOutView: some View {
    VStack(spacing: 0) {
      if appState.availableProviders.count > 1 {
        Form {
          Section("Service") {
            Picker("Provider", selection: $selectedProviderID) {
              ForEach(appState.availableProviders, id: \.providerID) { provider in
                Text(provider.displayName).tag(provider.providerID)
              }
            }
          }
        }
        .formStyle(.grouped)
        .frame(maxHeight: 120)
      }

      LoginView(
        viewModel: LoginViewModel(
          loginFields: appState.activeProvider.loginFields,
          loginAction: { credentials in
            try await appState.login(credentials: credentials)
          }
        ),
        providerName: appState.activeProvider.displayName
      )
    }
    .onChange(of: selectedProviderID) { _, newID in
      guard newID != appState.activeProvider.providerID,
            let provider = appState.availableProviders.first(where: { $0.providerID == newID })
      else { return }
      Task { await appState.switchProvider(to: provider) }
    }
  }
}
