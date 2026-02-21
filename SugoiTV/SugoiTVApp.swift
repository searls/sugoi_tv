import SugoiCore
import SwiftUI

@main
struct SugoiTVApp: App {
  #if os(macOS)
  @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
  #endif
  @State private var appState: AppState = {
    let keychain = KeychainService()
    let apiClient = APIClient()
    let provider = YoiTVProviderAdapter(keychain: keychain, apiClient: apiClient)
    return AppState(providers: [provider])
  }()
  #if os(macOS)
  @AppStorage("sidebarVisible") private var sidebarVisible = true
  #endif

  var body: some Scene {
    WindowGroup {
      SugoiTVRootView(appState: appState)
        #if os(macOS)
        .background(WindowAccessor())
        #endif
    }
    #if os(macOS)
    .windowStyle(.hiddenTitleBar)
    .defaultSize(width: 960, height: 540)
    #endif
    #if os(macOS)
    .commands {
      CommandGroup(replacing: .sidebar) {
        Button(sidebarVisible ? "Hide Sidebar" : "Show Sidebar") {
          NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
        }
        .keyboardShortcut("s", modifiers: [.command, .option])
      }
    }
    #endif

    #if os(macOS)
    Settings {
      SettingsView(appState: appState)
    }
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
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)

        // Snap the current frame to 16:9 (keep width, adjust height)
        var frame = window.frame
        let contentRect = window.contentRect(forFrameRect: frame)
        let targetHeight = contentRect.width * 9.0 / 16.0
        let chromeHeight = frame.height - contentRect.height
        frame.size.height = targetHeight + chromeHeight
        window.setFrame(frame, display: true)

        // Lock aspect ratio for all future resizes
        window.contentAspectRatio = NSSize(width: 16, height: 9)
      }
    }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif
