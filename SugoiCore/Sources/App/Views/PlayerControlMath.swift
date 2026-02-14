import Foundation

// MARK: - Extracted drag-gesture math (internal for testability)

enum PlayerControlMath {
  /// Map a horizontal drag location to a [0,1] fraction of the track width.
  static func scrubFraction(locationX: CGFloat, trackWidth: CGFloat) -> Double {
    guard trackWidth > 0 else { return 0 }
    return Double(min(max(locationX / trackWidth, 0), 1))
  }

  /// Map a [0,1] fraction to a playback position in seconds.
  static func scrubPosition(fraction: Double, duration: Double) -> Double {
    fraction * duration
  }

  /// Map a vertical drag location to a [0,1] volume (bottom = 0, top = 1).
  static func volumeFraction(locationY: CGFloat, trackHeight: CGFloat) -> Float {
    guard trackHeight > 0 else { return 0 }
    let fraction = 1.0 - (locationY / trackHeight)
    return Float(min(max(fraction, 0), 1))
  }

  /// SF Symbol name for the volume button.
  /// Returns `speaker.slash` during external playback (AirPlay) since the
  /// remote device controls its own volume and `AVPlayer.volume` has no effect.
  static func volumeIconName(volume: Float, isExternalPlayback: Bool) -> String {
    if isExternalPlayback { return "speaker.slash" }
    if volume == 0 { return "speaker.slash.fill" }
    if volume < 0.33 { return "speaker.wave.1.fill" }
    if volume < 0.66 { return "speaker.wave.2.fill" }
    return "speaker.wave.3.fill"
  }

  /// Format a time interval as "m:ss" or "h:mm:ss".
  static func formatTime(_ seconds: TimeInterval) -> String {
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
}

// MARK: - Controls visibility state machine

/// Testable state machine for player controls show/hide behavior.
/// Manages visibility, auto-hide scheduling, and platform-specific toggle logic.
@MainActor
@Observable
final class ControlsVisibilityState {
  private(set) var isVisible = true
  private var hideTask: Task<Void, Never>?

  /// Show controls and schedule auto-hide.
  func show(allowsAutoHide: Bool) {
    isVisible = true
    scheduleHide(allowsAutoHide: allowsAutoHide)
  }

  /// Toggle visibility (for iOS tap gesture).
  func toggle(allowsAutoHide: Bool) {
    if isVisible {
      isVisible = false
      cancelHide()
    } else {
      show(allowsAutoHide: allowsAutoHide)
    }
  }

  /// Hide controls immediately (e.g. mouse left the area).
  func hide() {
    cancelHide()
    isVisible = false
  }

  /// Schedule auto-hide after 3 seconds if allowed.
  func scheduleHide(allowsAutoHide: Bool) {
    hideTask?.cancel()
    guard allowsAutoHide else { return }
    hideTask = Task {
      try? await Task.sleep(for: .seconds(3))
      guard !Task.isCancelled else { return }
      isVisible = false
    }
  }

  /// Cancel any pending auto-hide (e.g. during scrubbing).
  func cancelHide() {
    hideTask?.cancel()
  }
}

/// Layout decisions for the player control bar.
/// Live mode is compact (no scrubber, no expansion); VOD mode expands to show the scrubber.
struct ControlBarLayout {
  let showsLiveBadge: Bool
  let showsScrubber: Bool
  let showsTimeLabels: Bool
  let showsSpeedControl: Bool
  let expandsToFillWidth: Bool
  let showsVolumeControl: Bool
  let isVolumeInteractive: Bool

  init(isLive: Bool, duration: TimeInterval, isExternalPlaybackActive: Bool = false) {
    showsLiveBadge = isLive
    showsScrubber = !isLive && duration > 0
    showsTimeLabels = !isLive
    showsSpeedControl = !isLive
    expandsToFillWidth = !isLive
    #if os(macOS)
    showsVolumeControl = true
    #else
    showsVolumeControl = false
    #endif
    isVolumeInteractive = !isExternalPlaybackActive
  }

  /// Whether a volume popover should be force-closed in response to an
  /// external-playback state change. Returns true when the popover is showing
  /// and external playback just became active.
  static func shouldCloseVolumePopover(
    showingPopover: Bool,
    isExternalPlaybackActive: Bool
  ) -> Bool {
    showingPopover && isExternalPlaybackActive
  }

  /// Whether the controls overlay is allowed to auto-hide after inactivity.
  /// Returns false when any interactive state is active or during AirPlay
  /// (toggling the overlay's layer tree disrupts the AirPlay route).
  static func allowsAutoHide(
    isScrubbing: Bool,
    showVolumePopover: Bool,
    isAirPlayPresenting: Bool,
    isExternalPlaybackActive: Bool
  ) -> Bool {
    if isScrubbing || showVolumePopover || isAirPlayPresenting { return false }
    if isExternalPlaybackActive { return false }
    return true
  }
}
