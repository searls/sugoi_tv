import AVFoundation
import AVKit
import SwiftUI

/// Wraps the platform system player (AVPlayerViewController / AVPlayerView)
/// to get native controls, PiP, AirPlay, Now Playing, and keyboard shortcuts for free.
public struct PlayerView: View {
  let playerManager: PlayerManager
  let isLive: Bool

  public init(playerManager: PlayerManager, isLive: Bool = false) {
    self.playerManager = playerManager
    self.isLive = isLive
  }

  public var body: some View {
    ZStack {
      if let player = playerManager.player {
        SystemPlayerView(player: player, isLive: isLive)
          .ignoresSafeArea()
      } else {
        Color.black
          .ignoresSafeArea()
      }

      // Error overlay (system player doesn't surface HLS errors well)
      if case .failed(let message) = playerManager.state {
        VStack(spacing: 12) {
          Image(systemName: "exclamationmark.triangle")
            .font(.largeTitle)
          Text(message)
            .multilineTextAlignment(.center)
          Button("Retry") { playerManager.play() }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
      }
    }
  }
}

// MARK: - Platform system player wrappers

#if os(macOS)
import AppKit

private struct SystemPlayerView: NSViewRepresentable {
  let player: AVPlayer
  let isLive: Bool

  func makeNSView(context: Context) -> AVPlayerView {
    let view = AVPlayerView()
    view.player = player
    view.controlsStyle = .floating
    view.showsFullScreenToggleButton = true
    // PiP disabled — AVPlayerView PiP breaks inside NSViewRepresentable
    view.allowsPictureInPicturePlayback = false
    return view
  }

  func updateNSView(_ nsView: AVPlayerView, context: Context) {
    if nsView.player !== player {
      nsView.player = player
    }
    // Speed clamping for live is handled by PlayerManager's rate observer
  }
}

#else
import UIKit

private struct SystemPlayerView: UIViewControllerRepresentable {
  let player: AVPlayer
  let isLive: Bool

  func makeUIViewController(context: Context) -> AVPlayerViewController {
    let vc = AVPlayerViewController()
    vc.player = player
    vc.allowsPictureInPicturePlayback = true
    vc.canStartPictureInPictureAutomaticallyFromInline = true
    if isLive {
      vc.speeds = [.init(rate: 1.0)]
    }
    return vc
  }

  func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
    if vc.player !== player {
      vc.player = player
    }
    if isLive {
      vc.speeds = [.init(rate: 1.0)]
    } else {
      vc.speeds = AVPlaybackSpeed.systemDefaultSpeeds
    }
  }
}
#endif
