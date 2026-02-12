import SugoiCore
import SwiftUI

@main
struct SugoiTVApp: App {
  @State private var appState = AppState()

  var body: some Scene {
    WindowGroup {
      SugoiTVRootView(appState: appState)
    }
  }
}
