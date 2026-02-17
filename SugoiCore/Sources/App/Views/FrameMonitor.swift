#if os(macOS)
import AppKit
#else
import UIKit
#endif
import QuartzCore

/// Detects main thread stalls using CADisplayLink (frame-accurate).
/// Logs when a frame takes significantly longer than the display refresh interval.
/// Remove this file when done.
@MainActor
final class FrameMonitor: NSObject {
  static let shared = FrameMonitor()

  private var displayLink: CADisplayLink?
  private var lastTimestamp: CFTimeInterval = 0
  private var dropCount = 0
  private var worstDrop: Double = 0
  private var summaryTimer: Timer?
  private var context: String = "playback"

  /// Call once at app launch.
  func start() {
    #if os(macOS)
    guard let screen = NSScreen.main else { return }
    displayLink = screen.displayLink(target: self, selector: #selector(tick))
    #else
    displayLink = CADisplayLink(target: self, selector: #selector(tick))
    #endif
    displayLink?.add(to: .main, forMode: .common)
    summaryTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.emitSummary()
      }
    }
    NSLog("⏱ FrameMonitor started")
  }

  @objc private func tick(_ link: CADisplayLink) {
    let ts = link.timestamp
    if lastTimestamp > 0 {
      let elapsedMs = (ts - lastTimestamp) * 1000
      let nominalMs = link.duration * 1000
      let threshold = nominalMs * 2.5
      if elapsedMs > threshold {
        dropCount += 1
        if elapsedMs > worstDrop { worstDrop = elapsedMs }
        if elapsedMs > nominalMs * 5 {
          NSLog("⏱ STALL %.0fms (%.0f frames) [%@]", elapsedMs, elapsedMs / nominalMs, context)
        }
      }
    }
    lastTimestamp = ts
  }

  private func emitSummary() {
    if dropCount > 0 {
      NSLog("⏱ 3s: %d drops, worst=%.0fms [%@]", dropCount, worstDrop, context)
      dropCount = 0
      worstDrop = 0
    }
  }

  func setContext(_ ctx: String) {
    context = ctx
    NSLog("⏱ CTX → %@", ctx)
  }
}
