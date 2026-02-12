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
      } else if let session = appState.session {
        authenticatedView(session: session)
      } else {
        loginView
      }
    }
    .task { await appState.restoreSession() }
  }

  private var loginView: some View {
    LoginView(
      viewModel: LoginViewModel(
        loginAction: { cid, password in
          try await appState.login(cid: cid, password: password)
        }
      )
    )
  }

  @ViewBuilder
  private func authenticatedView(session: AuthService.Session) -> some View {
    AuthenticatedContainer(appState: appState, session: session)
  }
}

/// Separate view so @State path lives at the right level
private struct AuthenticatedContainer: View {
  let appState: AppState
  let session: AuthService.Session
  @State private var path: [ChannelDTO] = []

  var body: some View {
    NavigationStack(path: $path) {
      ChannelListView(
        viewModel: ChannelListViewModel(
          channelService: appState.channelService,
          config: session.productConfig
        ),
        onSelectChannel: { channel in path.append(channel) }
      )
      .navigationDestination(for: ChannelDTO.self) { channel in
        ChannelPlayerView(channel: channel, session: session)
      }
      .toolbar {
        ToolbarItem(placement: .destructiveAction) {
          Button("Sign Out") {
            Task { await appState.logout() }
          }
        }
      }
    }
  }
}
