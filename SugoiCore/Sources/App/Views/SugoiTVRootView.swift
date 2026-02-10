import SwiftData
import SwiftUI

public struct SugoiTVRootView: View {
  @State private var authManager = AuthManager()
  @State private var channelStore = ChannelStore()

  public init() {}

  public var body: some View {
    Group {
      switch authManager.state {
      case .unknown:
        ProgressView("Loading...")
      case .loggedOut:
        LoginView()
      case .loggedIn:
        ChannelListView()
      }
    }
    .environment(authManager)
    .environment(channelStore)
    .modelContainer(for: [Channel.self, PlayRecord.self])
    .task {
      await authManager.initialize()
    }
  }
}
