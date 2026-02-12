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

/// Separate view so @State lives at the right level
private struct AuthenticatedContainer: View {
  let appState: AppState
  let session: AuthService.Session
  @State private var selectedChannel: ChannelDTO?

  var body: some View {
    NavigationSplitView {
      ChannelListView(
        viewModel: ChannelListViewModel(
          channelService: appState.channelService,
          config: session.productConfig
        ),
        selectedChannel: $selectedChannel
      )
      .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 400)
      .safeAreaInset(edge: .bottom) {
        Button("Sign Out") {
          Task { await appState.logout() }
        }
        .buttonStyle(.plain)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    } detail: {
      if let channel = selectedChannel {
        ChannelPlayerView(channel: channel, session: session)
      } else {
        ContentUnavailableView("Select a Channel", systemImage: "tv",
          description: Text("Choose a channel from the sidebar"))
      }
    }
    .navigationSplitViewStyle(.prominentDetail)
  }
}
