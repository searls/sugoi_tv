import Foundation
import Testing

@testable import SugoiCore

@Suite("PlayerControlMath.formatTime")
struct PlayerViewFormatTimeTests {
  @Test("Formats seconds correctly")
  func formatSeconds() {
    #expect(PlayerControlMath.formatTime(0) == "0:00")
    #expect(PlayerControlMath.formatTime(59) == "0:59")
    #expect(PlayerControlMath.formatTime(60) == "1:00")
    #expect(PlayerControlMath.formatTime(61) == "1:01")
    #expect(PlayerControlMath.formatTime(3599) == "59:59")
    #expect(PlayerControlMath.formatTime(3600) == "1:00:00")
    #expect(PlayerControlMath.formatTime(3661) == "1:01:01")
    #expect(PlayerControlMath.formatTime(7384) == "2:03:04")
  }

  @Test("Handles non-finite values")
  func nonFinite() {
    #expect(PlayerControlMath.formatTime(.infinity) == "0:00")
    #expect(PlayerControlMath.formatTime(.nan) == "0:00")
  }
}
