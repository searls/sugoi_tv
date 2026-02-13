import Foundation
import Testing

@testable import SugoiCore

#if os(macOS)

@Suite("PlayerControlMath.scrubFraction")
struct ScrubFractionTests {
  @Test("mid-track returns 0.5")
  func midTrack() {
    let result = PlayerControlMath.scrubFraction(locationX: 150, trackWidth: 300)
    #expect(result == 0.5)
  }

  @Test("at origin returns 0")
  func atOrigin() {
    let result = PlayerControlMath.scrubFraction(locationX: 0, trackWidth: 300)
    #expect(result == 0)
  }

  @Test("at end returns 1")
  func atEnd() {
    let result = PlayerControlMath.scrubFraction(locationX: 300, trackWidth: 300)
    #expect(result == 1)
  }

  @Test("negative location clamps to 0")
  func negativeClamps() {
    let result = PlayerControlMath.scrubFraction(locationX: -50, trackWidth: 300)
    #expect(result == 0)
  }

  @Test("beyond end clamps to 1")
  func beyondEndClamps() {
    let result = PlayerControlMath.scrubFraction(locationX: 500, trackWidth: 300)
    #expect(result == 1)
  }

  @Test("zero width returns 0")
  func zeroWidth() {
    let result = PlayerControlMath.scrubFraction(locationX: 100, trackWidth: 0)
    #expect(result == 0)
  }
}

@Suite("PlayerControlMath.scrubPosition")
struct ScrubPositionTests {
  @Test("maps fraction to duration")
  func mapsFraction() {
    let result = PlayerControlMath.scrubPosition(fraction: 0.5, duration: 120)
    #expect(result == 60)
  }

  @Test("zero fraction returns zero")
  func zeroFraction() {
    let result = PlayerControlMath.scrubPosition(fraction: 0, duration: 120)
    #expect(result == 0)
  }

  @Test("full fraction returns full duration")
  func fullFraction() {
    let result = PlayerControlMath.scrubPosition(fraction: 1, duration: 3600)
    #expect(result == 3600)
  }

  @Test("zero duration returns zero")
  func zeroDuration() {
    let result = PlayerControlMath.scrubPosition(fraction: 0.5, duration: 0)
    #expect(result == 0)
  }
}

@Suite("PlayerControlMath.volumeFraction")
struct VolumeFractionTests {
  @Test("top of track returns 1 (full volume)")
  func topIsFullVolume() {
    let result = PlayerControlMath.volumeFraction(locationY: 0, trackHeight: 100)
    #expect(result == 1)
  }

  @Test("bottom of track returns 0 (muted)")
  func bottomIsMuted() {
    let result = PlayerControlMath.volumeFraction(locationY: 100, trackHeight: 100)
    #expect(result == 0)
  }

  @Test("mid-track returns 0.5")
  func midTrack() {
    let result = PlayerControlMath.volumeFraction(locationY: 50, trackHeight: 100)
    #expect(result == 0.5)
  }

  @Test("above top clamps to 1")
  func aboveTopClamps() {
    let result = PlayerControlMath.volumeFraction(locationY: -30, trackHeight: 100)
    #expect(result == 1)
  }

  @Test("below bottom clamps to 0")
  func belowBottomClamps() {
    let result = PlayerControlMath.volumeFraction(locationY: 150, trackHeight: 100)
    #expect(result == 0)
  }

  @Test("zero height returns 0")
  func zeroHeight() {
    let result = PlayerControlMath.volumeFraction(locationY: 50, trackHeight: 0)
    #expect(result == 0)
  }
}

#endif
