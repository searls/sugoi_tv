#if os(macOS)
import AppKit
import Testing

@testable import SugoiCore

@Suite("AppDelegate")
@MainActor
struct AppDelegateTests {
  @Test func terminatesAfterLastWindowClosed() {
    let delegate = AppDelegate()
    #expect(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
  }
}
#endif
