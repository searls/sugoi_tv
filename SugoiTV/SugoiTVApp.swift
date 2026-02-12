import SugoiCore
import SwiftUI

@main
struct SugoiTVApp: App {
  @State private var appState = AppState()

  var body: some Scene {
    WindowGroup {
      SugoiTVRootView(appState: appState)
    }
    #if os(macOS)
    .windowStyle(.hiddenTitleBar)
    #endif
  }
}

#if os(macOS)
import AppKit

/// Accesses the hosting NSWindow to lock its aspect ratio to 16:9.
private struct WindowAccessor: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async {
      if let window = view.window {
        window.contentAspectRatio = NSSize(width: 16, height: 9)
      }
    }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif
