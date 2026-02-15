import AVFoundation
import AVKit
import SwiftUI

#if !os(tvOS)

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: Custom player container

/// Owns PiP state and wires together video layer + controls overlay.
struct CustomPlayerView: View {
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
    #if os(macOS)
    .focusable()
    .onKeyPress(.space) {
      playerManager.togglePlayPause()
      return .handled
    }
    #endif
  }
}

// MARK: Player controls overlay (Liquid Glass)

/// Single Liquid Glass bar with borderless buttons inside — no nested glass.
/// macOS: auto-shows on mouse hover, hides after 3s inactivity.
/// iOS: tap to toggle visibility, auto-hides after 3s.
struct PlayerControlsOverlay: View {
  let playerManager: PlayerManager
  let player: AVPlayer
  let pipController: AVPictureInPictureController?

  @State private var visibility = ControlsVisibilityState()
  @State private var isScrubbing = false
  @State private var scrubPosition: TimeInterval = 0
  @State private var isAirPlayPresenting = false
  @State private var playbackRate: Float = 1.0

  #if os(macOS)
  @State private var volume: Float = 1.0
  @State private var showVolumePopover = false
  #endif

  private var layout: ControlBarLayout {
    ControlBarLayout(
      isLive: playerManager.isLive,
      duration: playerManager.duration,
      isExternalPlaybackActive: playerManager.isExternalPlaybackActive
    )
  }

  private var allowsAutoHide: Bool {
    #if os(macOS)
    ControlBarLayout.allowsAutoHide(
      isScrubbing: isScrubbing,
      showVolumePopover: showVolumePopover,
      isAirPlayPresenting: isAirPlayPresenting,
      isExternalPlaybackActive: playerManager.isExternalPlaybackActive
    )
    #else
    ControlBarLayout.allowsAutoHide(
      isScrubbing: isScrubbing,
      showVolumePopover: false,
      isAirPlayPresenting: isAirPlayPresenting,
      isExternalPlaybackActive: playerManager.isExternalPlaybackActive
    )
    #endif
  }

  var body: some View {
    ZStack(alignment: .bottom) {
      // Invisible interaction region covering the full player area
      Color.clear
        .contentShape(Rectangle())
        #if os(macOS)
        .onHover { hovering in
          if hovering {
            visibility.show(allowsAutoHide: allowsAutoHide)
          } else {
            visibility.scheduleHide(allowsAutoHide: allowsAutoHide)
          }
        }
        .onContinuousHover { phase in
          if case .active = phase {
            visibility.show(allowsAutoHide: allowsAutoHide)
          }
        }
        #else
        .onTapGesture {
          visibility.toggle(allowsAutoHide: allowsAutoHide)
        }
        #endif

      controlsBar
        .opacity(visibility.isVisible ? 1 : 0)
        .offset(y: visibility.isVisible ? 0 : 20)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
    .animation(.easeInOut(duration: 0.25), value: visibility.isVisible)
    .onAppear {
      #if os(macOS)
      volume = player.volume
      #endif
      visibility.scheduleHide(allowsAutoHide: allowsAutoHide)
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
        visibility.scheduleHide(allowsAutoHide: allowsAutoHide)
      } label: {
        Image(systemName: playerManager.state == .playing ? "pause.fill" : "play.fill")
          .font(.title2)
          .frame(width: 36, height: 36)
      }
      .buttonStyle(.borderless)
      .accessibilityIdentifier("playPauseButton")

      // Time + scrubber (VOD) or LIVE badge
      if layout.showsLiveBadge {
        HStack(spacing: 4) {
          Circle().fill(.red).frame(width: 8, height: 8)
          Text("LIVE").font(.caption.bold())
        }
        .accessibilityIdentifier("liveBadge")
      }

      if layout.showsTimeLabels {
        Text(PlayerControlMath.formatTime(currentDisplayTime))
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
                  visibility.cancelHide()
                }
                let pct = PlayerControlMath.scrubFraction(locationX: value.location.x, trackWidth: width)
                scrubPosition = PlayerControlMath.scrubPosition(fraction: pct, duration: playerManager.duration)
              }
              .onEnded { _ in
                playerManager.seek(to: scrubPosition)
                isScrubbing = false
                visibility.scheduleHide(allowsAutoHide: allowsAutoHide)
              }
          )
        }
      } else if layout.expandsToFillWidth {
        Spacer()
      }

      if layout.showsTimeLabels {
        Text(PlayerControlMath.formatTime(playerManager.duration))
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }

      // Playback speed (VOD only)
      if layout.showsSpeedControl {
        speedMenu
      }

      #if os(macOS)
      // Volume button + vertical popover (macOS only; iOS uses hardware buttons)
      if layout.showsVolumeControl {
        volumeButton
      }
      #endif

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
    .tint(.primary)
    .glassEffect(in: .rect(cornerRadius: 16))
    .frame(maxWidth: 640)
    .accessibilityIdentifier("playerControlsBar")
  }

  // MARK: - Speed menu

  private var speedMenu: some View {
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
    #if os(macOS)
    .menuStyle(.borderlessButton)
    #else
    .menuStyle(.button)
    .buttonStyle(.borderless)
    #endif
    .menuIndicator(.hidden)
  }

  // MARK: - Volume (macOS only)

  #if os(macOS)
  private var volumeButton: some View {
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
  }

  private var volumeIcon: String {
    PlayerControlMath.volumeIconName(
      volume: volume,
      isExternalPlayback: playerManager.isExternalPlaybackActive
    )
  }
  #endif

  // MARK: - Helpers

  private var currentDisplayTime: TimeInterval {
    isScrubbing ? scrubPosition : playerManager.currentTime
  }
}
#endif
