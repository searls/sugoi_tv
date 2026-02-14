import AVFoundation
import AVKit
import SwiftUI

/// Cross-platform video player.
/// macOS uses AVPlayerLayer + custom SwiftUI controls with Liquid Glass styling.
/// iOS/tvOS uses SwiftUI's VideoPlayer with system controls.
public struct PlayerView: View {
  let playerManager: PlayerManager

  public init(playerManager: PlayerManager) {
    self.playerManager = playerManager
  }

  public var body: some View {
    Group {
      if let player = playerManager.player {
        platformPlayer(player: player)
          .ignoresSafeArea()
      } else {
        Color.black
          .ignoresSafeArea()
      }
    }
    .accessibilityIdentifier("playerView")
    .alert("Playback Error", isPresented: showingError) {
      Button("Retry") { playerManager.retry() }
      Button("Dismiss", role: .cancel) { playerManager.clearError() }
    } message: {
      Text(errorMessage)
    }
  }

  @ViewBuilder
  private func platformPlayer(player: AVPlayer) -> some View {
    #if os(macOS)
    MacOSPlayerView(playerManager: playerManager, player: player)
    #else
    VideoPlayer(player: player)
    #endif
  }

  private var showingError: Binding<Bool> {
    Binding(
      get: { if case .failed = playerManager.state { true } else { false } },
      set: { if !$0 { playerManager.clearError() } }
    )
  }

  private var errorMessage: String {
    if case .failed(let msg) = playerManager.state { return msg }
    return ""
  }
}

// MARK: - macOS: Custom player with Liquid Glass controls

#if os(macOS)
import AppKit

// MARK: NSView backed by AVPlayerLayer

/// NSView backed by AVPlayerLayer with black background for letterbox bars.
/// Returns nil from hitTest so mouse events pass through to SwiftUI controls.
class PassthroughPlayerNSView: NSView {
  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func makeBackingLayer() -> CALayer {
    let layer = AVPlayerLayer()
    layer.backgroundColor = NSColor.black.cgColor
    return layer
  }

  var playerLayer: AVPlayerLayer {
    layer as! AVPlayerLayer
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }
}

/// Renders video via AVPlayerLayer with event passthrough.
/// Optionally vends an AVPictureInPictureController via binding.
struct PassthroughPlayerView: NSViewRepresentable {
  let player: AVPlayer
  var pipController: Binding<AVPictureInPictureController?>? = nil

  static func makeConfiguredView(player: AVPlayer) -> PassthroughPlayerNSView {
    let view = PassthroughPlayerNSView()
    view.playerLayer.player = player
    view.playerLayer.videoGravity = .resizeAspect
    return view
  }

  func makeNSView(context: Context) -> PassthroughPlayerNSView {
    let view = Self.makeConfiguredView(player: player)
    if let binding = pipController,
       AVPictureInPictureController.isPictureInPictureSupported() {
      let pip = AVPictureInPictureController(playerLayer: view.playerLayer)
      DispatchQueue.main.async {
        binding.wrappedValue = pip
      }
    }
    return view
  }

  func updateNSView(_ nsView: PassthroughPlayerNSView, context: Context) {
    if nsView.playerLayer.player !== player {
      nsView.playerLayer.player = player
    }
  }
}

/// Wraps AVRoutePickerView for AirPlay output selection.
struct AirPlayPickerView: NSViewRepresentable {
  let player: AVPlayer
  var onPresentingRoutesChanged: ((Bool) -> Void)? = nil

  static func makeConfiguredView(player: AVPlayer) -> AVRoutePickerView {
    let picker = AVRoutePickerView()
    picker.player = player
    picker.isRoutePickerButtonBordered = false
    return picker
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(onPresentingRoutesChanged: onPresentingRoutesChanged)
  }

  func makeNSView(context: Context) -> AVRoutePickerView {
    let picker = Self.makeConfiguredView(player: player)
    picker.delegate = context.coordinator
    return picker
  }

  func updateNSView(_ nsView: AVRoutePickerView, context: Context) {
    if nsView.player !== player {
      nsView.player = player
    }
    context.coordinator.onPresentingRoutesChanged = onPresentingRoutesChanged
  }

  final class Coordinator: NSObject, AVRoutePickerViewDelegate {
    var onPresentingRoutesChanged: ((Bool) -> Void)?

    init(onPresentingRoutesChanged: ((Bool) -> Void)?) {
      self.onPresentingRoutesChanged = onPresentingRoutesChanged
    }

    func routePickerViewWillBeginPresentingRoutes(_ routePickerView: AVRoutePickerView) {
      onPresentingRoutesChanged?(true)
    }

    func routePickerViewDidEndPresentingRoutes(_ routePickerView: AVRoutePickerView) {
      onPresentingRoutesChanged?(false)
    }
  }
}

// MARK: Format helper

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

// MARK: macOS player container

/// Owns PiP state and wires together video layer + controls overlay.
private struct MacOSPlayerView: View {
  let playerManager: PlayerManager
  let player: AVPlayer
  @State private var pipController: AVPictureInPictureController?

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      PassthroughPlayerView(player: player, pipController: $pipController)
      PlayerControlsOverlay(
        playerManager: playerManager,
        player: player,
        pipController: pipController
      )
    }
    .onKeyPress(.space) {
      playerManager.togglePlayPause()
      return .handled
    }
  }
}

// MARK: Player controls overlay (Liquid Glass)

/// Single Liquid Glass bar with borderless buttons inside — no nested glass.
/// Auto-shows on mouse hover, hides after 3s inactivity.
private struct PlayerControlsOverlay: View {
  let playerManager: PlayerManager
  let player: AVPlayer
  let pipController: AVPictureInPictureController?

  @State private var isVisible = true
  @State private var hideTask: Task<Void, Never>?
  @State private var isScrubbing = false
  @State private var scrubPosition: TimeInterval = 0
  @State private var volume: Float = 1.0
  @State private var showVolumePopover = false
  @State private var isAirPlayPresenting = false
  @State private var playbackRate: Float = 1.0

  private var layout: ControlBarLayout {
    ControlBarLayout(
      isLive: playerManager.isLive,
      duration: playerManager.duration,
      isExternalPlaybackActive: playerManager.isExternalPlaybackActive
    )
  }

  var body: some View {
    ZStack(alignment: .bottom) {
      // Invisible hover region covering the full player area
      Color.clear
        .contentShape(Rectangle())
        .onHover { hovering in
          if hovering { showControls() } else { scheduleHide() }
        }
        .onContinuousHover { phase in
          if case .active = phase { showControls() }
        }

      controlsBar
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 20)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
    .animation(.easeInOut(duration: 0.25), value: isVisible)
    .onAppear {
      volume = player.volume
      scheduleHide()
    }
  }

  // Single glass bar — all buttons use .borderless to avoid glass-in-glass
  private var controlsBar: some View {
    HStack(spacing: 16) {
      // Play/pause
      Button {
        playerManager.togglePlayPause()
        if playerManager.state == .playing && playbackRate != 1.0 {
          player.rate = playbackRate
        }
        scheduleHide()
      } label: {
        Image(systemName: playerManager.state == .playing ? "pause.fill" : "play.fill")
          .font(.title2)
          .frame(width: 36, height: 36)
      }
      .buttonStyle(.borderless)

      // Time + scrubber (VOD) or LIVE badge
      if layout.showsLiveBadge {
        HStack(spacing: 4) {
          Circle().fill(.red).frame(width: 8, height: 8)
          Text("LIVE").font(.caption.bold())
        }
      }

      if layout.showsTimeLabels {
        Text(formatTime(currentDisplayTime))
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }

      if layout.showsScrubber {
        GeometryReader { geo in
          let width = geo.size.width
          let fraction = playerManager.duration > 0
            ? CGFloat(currentDisplayTime / playerManager.duration)
            : 0
          ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
              .fill(.tertiary)
            RoundedRectangle(cornerRadius: 2)
              .fill(.white)
              .frame(width: width * min(max(fraction, 0), 1))
          }
          .frame(height: 4)
          .frame(maxHeight: .infinity)
          .contentShape(Rectangle())
          .gesture(
            DragGesture(minimumDistance: 0)
              .onChanged { value in
                if !isScrubbing {
                  isScrubbing = true
                  scrubPosition = playerManager.currentTime
                  cancelHide()
                }
                let pct = PlayerControlMath.scrubFraction(locationX: value.location.x, trackWidth: width)
                scrubPosition = PlayerControlMath.scrubPosition(fraction: pct, duration: playerManager.duration)
              }
              .onEnded { _ in
                playerManager.seek(to: scrubPosition)
                isScrubbing = false
                scheduleHide()
              }
          )
        }
      } else if layout.expandsToFillWidth {
        Spacer()
      }

      if layout.showsTimeLabels {
        Text(formatTime(playerManager.duration))
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }

      // Playback speed (VOD only)
      if layout.showsSpeedControl {
        Menu {
          ForEach([0.5, 1.0, 1.25, 1.5, 2.0] as [Float], id: \.self) { rate in
            Button {
              playbackRate = rate
              if playerManager.state == .playing {
                player.rate = rate
              }
            } label: {
              HStack {
                Text(rate == 1.0 ? "1x" : String(format: "%gx", rate))
                if playbackRate == rate {
                  Image(systemName: "checkmark")
                }
              }
            }
          }
        } label: {
          Text(playbackRate == 1.0 ? "1x" : String(format: "%gx", playbackRate))
            .font(.caption.monospacedDigit())
            .frame(width: 32, height: 28)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
      }

      // Volume button + vertical popover
      Button {
        showVolumePopover.toggle()
      } label: {
        Image(systemName: volumeIcon)
          .font(.body)
          .frame(width: 28, height: 28)
      }
      .buttonStyle(.borderless)
      .disabled(!layout.isVolumeInteractive)
      .popover(isPresented: $showVolumePopover, arrowEdge: .bottom) {
        VStack(spacing: 8) {
          GeometryReader { geo in
            let height = geo.size.height
            ZStack(alignment: .bottom) {
              RoundedRectangle(cornerRadius: 2)
                .fill(.tertiary)
              RoundedRectangle(cornerRadius: 2)
                .fill(.white)
                .frame(height: height * CGFloat(volume))
            }
            .frame(width: 4)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
              DragGesture(minimumDistance: 0)
                .onChanged { value in
                  volume = PlayerControlMath.volumeFraction(locationY: value.location.y, trackHeight: height)
                }
            )
          }
          .frame(width: 32, height: 100)
          Image(systemName: volumeIcon)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(8)
        .onChange(of: volume) { _, newValue in
          player.volume = newValue
        }
      }
      .onChange(of: playerManager.isExternalPlaybackActive) { _, isExternal in
        if ControlBarLayout.shouldCloseVolumePopover(
          showingPopover: showVolumePopover,
          isExternalPlaybackActive: isExternal
        ) {
          showVolumePopover = false
        }
      }

      // PiP
      if let pip = pipController {
        Button {
          if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
          } else {
            pip.startPictureInPicture()
          }
        } label: {
          Image(systemName: "pip.enter")
            .font(.body)
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.borderless)
      }

      // AirPlay
      AirPlayPickerView(player: player) { presenting in
        isAirPlayPresenting = presenting
      }
      .frame(width: 28, height: 28)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .glassEffect(in: .rect(cornerRadius: 16))
    .frame(maxWidth: 640)
  }

  private var currentDisplayTime: TimeInterval {
    isScrubbing ? scrubPosition : playerManager.currentTime
  }

  private var volumeIcon: String {
    PlayerControlMath.volumeIconName(
      volume: volume,
      isExternalPlayback: playerManager.isExternalPlaybackActive
    )
  }

  private func showControls() {
    isVisible = true
    scheduleHide()
  }

  private func scheduleHide() {
    hideTask?.cancel()
    guard ControlBarLayout.allowsAutoHide(
      isScrubbing: isScrubbing,
      showVolumePopover: showVolumePopover,
      isAirPlayPresenting: isAirPlayPresenting,
      isExternalPlaybackActive: playerManager.isExternalPlaybackActive
    ) else { return }
    hideTask = Task {
      try? await Task.sleep(for: .seconds(3))
      guard !Task.isCancelled, !isScrubbing else { return }
      isVisible = false
    }
  }

  private func cancelHide() {
    hideTask?.cancel()
  }
}
#endif

// MARK: - Preview

#if DEBUG
private struct PlayerViewPreview: View {
  @State private var manager = PlayerManager()

  var body: some View {
    PlayerView(playerManager: manager)
      .onAppear {
        if let url = Bundle.module.url(
          forResource: "test-video",
          withExtension: "mp4",
          subdirectory: "PreviewContent"
        ) {
          manager.loadVODStream(url: url, referer: "http://preview.local")
        }
      }
  }
}

#Preview("Player") {
  PlayerViewPreview()
}

private struct PlayerViewLivePreview: View {
  @State private var manager = PlayerManager()

  var body: some View {
    PlayerView(playerManager: manager)
      .onAppear {
        manager.loadLiveStream(
          url: URL(string: "http://example.com/test.M3U8")!,
          referer: "http://preview.local"
        )
      }
  }
}

#Preview("Player (Live)") {
  PlayerViewLivePreview()
}

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
}

/// Layout decisions for the player control bar.
/// Live mode is compact (no scrubber, no expansion); VOD mode expands to show the scrubber.
struct ControlBarLayout {
  let showsLiveBadge: Bool
  let showsScrubber: Bool
  let showsTimeLabels: Bool
  let showsSpeedControl: Bool
  let expandsToFillWidth: Bool
  let isVolumeInteractive: Bool

  init(isLive: Bool, duration: TimeInterval, isExternalPlaybackActive: Bool = false) {
    showsLiveBadge = isLive
    showsScrubber = !isLive && duration > 0
    showsTimeLabels = !isLive
    showsSpeedControl = !isLive
    expandsToFillWidth = !isLive
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
#endif

