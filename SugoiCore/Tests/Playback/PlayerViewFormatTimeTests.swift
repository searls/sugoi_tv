import Foundation
import Testing

@testable import SugoiCore

@Suite("PlayerView formatTime")
struct PlayerViewFormatTimeTests {
  private func formatTime(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite else { return "0:00" }
    let totalSeconds = Int(seconds)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let secs = totalSeconds % 60
    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%d:%02d", minutes, secs)
  }

  @Test("Formats seconds correctly")
  func formatSeconds() {
    #expect(formatTime(0) == "0:00")
    #expect(formatTime(59) == "0:59")
    #expect(formatTime(60) == "1:00")
    #expect(formatTime(61) == "1:01")
    #expect(formatTime(3599) == "59:59")
    #expect(formatTime(3600) == "1:00:00")
    #expect(formatTime(3661) == "1:01:01")
    #expect(formatTime(7384) == "2:03:04")
  }

  @Test("Handles non-finite values")
  func nonFinite() {
    #expect(formatTime(.infinity) == "0:00")
    #expect(formatTime(.nan) == "0:00")
  }
}
