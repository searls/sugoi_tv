import Foundation
import Testing

@testable import SugoiCore

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

@Suite("PlayerControlMath.volumeIconName")
struct VolumeIconNameTests {
  @Test("returns speaker.slash during external playback regardless of volume")
  func externalPlaybackShowsSlash() {
    #expect(PlayerControlMath.volumeIconName(volume: 0, isExternalPlayback: true) == "speaker.slash")
    #expect(PlayerControlMath.volumeIconName(volume: 0.5, isExternalPlayback: true) == "speaker.slash")
    #expect(PlayerControlMath.volumeIconName(volume: 1.0, isExternalPlayback: true) == "speaker.slash")
  }

  @Test("returns speaker.slash.fill when muted locally")
  func mutedShowsSlashFill() {
    #expect(PlayerControlMath.volumeIconName(volume: 0, isExternalPlayback: false) == "speaker.slash.fill")
  }

  @Test("returns wave.1 for low volume")
  func lowVolume() {
    #expect(PlayerControlMath.volumeIconName(volume: 0.2, isExternalPlayback: false) == "speaker.wave.1.fill")
  }

  @Test("returns wave.2 for medium volume")
  func mediumVolume() {
    #expect(PlayerControlMath.volumeIconName(volume: 0.5, isExternalPlayback: false) == "speaker.wave.2.fill")
  }

  @Test("returns wave.3 for high volume")
  func highVolume() {
    #expect(PlayerControlMath.volumeIconName(volume: 0.8, isExternalPlayback: false) == "speaker.wave.3.fill")
    #expect(PlayerControlMath.volumeIconName(volume: 1.0, isExternalPlayback: false) == "speaker.wave.3.fill")
  }
}

@Suite("ControlBarLayout")
struct ControlBarLayoutTests {
  @Test("live mode is compact — no scrubber, no time labels, no speed, no expansion")
  func liveMode() {
    let layout = ControlBarLayout(isLive: true, duration: 0)

    #expect(layout.showsLiveBadge == true)
    #expect(layout.showsScrubber == false)
    #expect(layout.showsTimeLabels == false)
    #expect(layout.showsSpeedControl == false)
    #expect(layout.expandsToFillWidth == false)
  }

  @Test("live mode stays compact even with nonzero duration")
  func liveModeWithDuration() {
    let layout = ControlBarLayout(isLive: true, duration: 3600)

    #expect(layout.showsLiveBadge == true)
    #expect(layout.showsScrubber == false)
    #expect(layout.expandsToFillWidth == false)
  }

  @Test("VOD with duration shows scrubber and expands")
  func vodWithDuration() {
    let layout = ControlBarLayout(isLive: false, duration: 120)

    #expect(layout.showsLiveBadge == false)
    #expect(layout.showsScrubber == true)
    #expect(layout.showsTimeLabels == true)
    #expect(layout.showsSpeedControl == true)
    #expect(layout.expandsToFillWidth == true)
  }

  @Test("VOD with zero duration hides scrubber but still expands")
  func vodZeroDuration() {
    let layout = ControlBarLayout(isLive: false, duration: 0)

    #expect(layout.showsLiveBadge == false)
    #expect(layout.showsScrubber == false)
    #expect(layout.showsTimeLabels == true)
    #expect(layout.showsSpeedControl == true)
    #expect(layout.expandsToFillWidth == true)
  }

  #if os(macOS)
  @Test("macOS shows volume control")
  func macOSShowsVolumeControl() {
    let layout = ControlBarLayout(isLive: false, duration: 120)
    #expect(layout.showsVolumeControl == true)
  }
  #else
  @Test("iOS hides volume control (hardware buttons)")
  func iOSHidesVolumeControl() {
    let layout = ControlBarLayout(isLive: false, duration: 120)
    #expect(layout.showsVolumeControl == false)
  }
  #endif

  @Test("volume is interactive by default (no external playback)")
  func volumeInteractiveByDefault() {
    let layout = ControlBarLayout(isLive: false, duration: 120)
    #expect(layout.isVolumeInteractive == true)
  }

  @Test("volume is not interactive during external playback (AirPlay)")
  func volumeDisabledDuringAirPlay() {
    let layout = ControlBarLayout(isLive: false, duration: 120, isExternalPlaybackActive: true)
    #expect(layout.isVolumeInteractive == false)
  }

  @Test("volume is not interactive during external playback in live mode")
  func volumeDisabledDuringAirPlayLive() {
    let layout = ControlBarLayout(isLive: true, duration: 0, isExternalPlaybackActive: true)
    #expect(layout.isVolumeInteractive == false)
  }
}

@Suite("ControlBarLayout.shouldCloseVolumePopover")
struct ShouldCloseVolumePopoverTests {
  @Test("closes popover when external playback activates and popover is showing")
  func closesWhenAirPlayActivates() {
    let result = ControlBarLayout.shouldCloseVolumePopover(
      showingPopover: true,
      isExternalPlaybackActive: true
    )
    #expect(result == true)
  }

  @Test("does not close popover when external playback deactivates")
  func noCloseWhenAirPlayEnds() {
    let result = ControlBarLayout.shouldCloseVolumePopover(
      showingPopover: true,
      isExternalPlaybackActive: false
    )
    #expect(result == false)
  }

  @Test("no-op when popover is already hidden")
  func noOpWhenPopoverHidden() {
    let result = ControlBarLayout.shouldCloseVolumePopover(
      showingPopover: false,
      isExternalPlaybackActive: true
    )
    #expect(result == false)
  }
}

@Suite("ControlBarLayout.allowsAutoHide")
struct AllowsAutoHideTests {
  @Test("allows auto-hide when nothing interactive is active")
  func defaultAllows() {
    let result = ControlBarLayout.allowsAutoHide(
      isScrubbing: false,
      showVolumePopover: false,
      isAirPlayPresenting: false,
      isExternalPlaybackActive: false
    )
    #expect(result == true)
  }

  @Test("blocks auto-hide during AirPlay to prevent route disruption")
  func blockedDuringAirPlay() {
    let result = ControlBarLayout.allowsAutoHide(
      isScrubbing: false,
      showVolumePopover: false,
      isAirPlayPresenting: false,
      isExternalPlaybackActive: true
    )
    #expect(result == false)
  }

  @Test("blocks auto-hide while scrubbing")
  func blockedWhileScrubbing() {
    let result = ControlBarLayout.allowsAutoHide(
      isScrubbing: true,
      showVolumePopover: false,
      isAirPlayPresenting: false,
      isExternalPlaybackActive: false
    )
    #expect(result == false)
  }

  @Test("blocks auto-hide while volume popover is open")
  func blockedWhileVolumeOpen() {
    let result = ControlBarLayout.allowsAutoHide(
      isScrubbing: false,
      showVolumePopover: true,
      isAirPlayPresenting: false,
      isExternalPlaybackActive: false
    )
    #expect(result == false)
  }

  @Test("blocks auto-hide while AirPlay picker is presenting")
  func blockedWhileAirPlayPresenting() {
    let result = ControlBarLayout.allowsAutoHide(
      isScrubbing: false,
      showVolumePopover: false,
      isAirPlayPresenting: true,
      isExternalPlaybackActive: false
    )
    #expect(result == false)
  }
}

@Suite("ControlsVisibilityState")
struct ControlsVisibilityStateTests {
  @Test("starts visible")
  @MainActor
  func startsVisible() {
    let state = ControlsVisibilityState()
    #expect(state.isVisible == true)
  }

  @Test("hide sets isVisible to false")
  @MainActor
  func hideWorks() {
    let state = ControlsVisibilityState()
    state.hide()
    #expect(state.isVisible == false)
  }

  @Test("show after hide restores visibility")
  @MainActor
  func showAfterHide() {
    let state = ControlsVisibilityState()
    state.hide()
    state.show(allowsAutoHide: false)
    #expect(state.isVisible == true)
  }

  @Test("toggle hides when visible")
  @MainActor
  func toggleHidesWhenVisible() {
    let state = ControlsVisibilityState()
    #expect(state.isVisible == true)
    state.toggle(allowsAutoHide: false)
    #expect(state.isVisible == false)
  }

  @Test("toggle shows when hidden")
  @MainActor
  func toggleShowsWhenHidden() {
    let state = ControlsVisibilityState()
    state.hide()
    state.toggle(allowsAutoHide: false)
    #expect(state.isVisible == true)
  }

  @Test("scheduleHide does not hide immediately")
  @MainActor
  func scheduleHideNotImmediate() {
    let state = ControlsVisibilityState()
    state.scheduleHide(allowsAutoHide: true)
    #expect(state.isVisible == true)
  }

  @Test("scheduleHide with allowsAutoHide false keeps visible")
  @MainActor
  func scheduleHideBlockedKeepsVisible() async throws {
    let state = ControlsVisibilityState()
    state.scheduleHide(allowsAutoHide: false)
    try await Task.sleep(for: .milliseconds(100))
    #expect(state.isVisible == true)
  }

  @Test("cancelHide prevents auto-hide")
  @MainActor
  func cancelHidePreventsHide() async throws {
    let state = ControlsVisibilityState()
    state.scheduleHide(allowsAutoHide: true)
    state.cancelHide()
    try await Task.sleep(for: .milliseconds(100))
    #expect(state.isVisible == true)
  }
}
