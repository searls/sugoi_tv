#if os(macOS)
import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
  public override init() { super.init() }

  public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }
}
#endif
