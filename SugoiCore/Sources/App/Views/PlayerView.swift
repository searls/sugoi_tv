import AVFoundation
import SwiftUI

/// Wraps AVPlayerViewController for SwiftUI
public struct PlayerView: View {
  let playerManager: PlayerManager

  public init(playerManager: PlayerManager) {
    self.playerManager = playerManager
  }

  public var body: some View {
    ZStack {
      // Video layer
      if let player = playerManager.player {
        VideoPlayerRepresentable(player: player)
          .ignoresSafeArea()
      } else {
        Color.black
          .ignoresSafeArea()
      }

      // Overlay controls
      VStack {
        Spacer()
        controlsOverlay
      }
    }
    .overlay {
      if playerManager.state == .loading {
        ProgressView()
          .scaleEffect(1.5)
      }

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

  private var controlsOverlay: some View {
    VStack(spacing: 8) {
      // Progress bar (VOD only)
      if !playerManager.isLive && playerManager.duration > 0 {
        ProgressView(
          value: playerManager.currentTime,
          total: playerManager.duration
        )
        .tint(.white)
      }

      HStack(spacing: 20) {
        // Time display
        if playerManager.isLive {
          HStack(spacing: 4) {
            Circle()
              .fill(.red)
              .frame(width: 8, height: 8)
            Text("LIVE")
              .font(.caption.bold())
          }
        } else {
          Text(formatTime(playerManager.currentTime))
            .font(.caption.monospacedDigit())
          Text("/")
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(formatTime(playerManager.duration))
            .font(.caption.monospacedDigit())
        }

        Spacer()

        // Transport controls
        if !playerManager.isLive {
          Button { playerManager.skipBackward() } label: {
            Image(systemName: "gobackward.15")
          }
        }

        Button { playerManager.togglePlayPause() } label: {
          Image(systemName: playerManager.state == .playing ? "pause.fill" : "play.fill")
            .font(.title2)
        }

        if !playerManager.isLive {
          Button { playerManager.skipForward() } label: {
            Image(systemName: "goforward.15")
          }
        }
      }
      .foregroundStyle(.white)
    }
    .padding()
    .background(
      LinearGradient(
        colors: [.clear, .black.opacity(0.6)],
        startPoint: .top,
        endPoint: .bottom
      )
    )
  }

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
}

// MARK: - Platform video view

#if os(macOS)
import AppKit

struct VideoPlayerRepresentable: NSViewRepresentable {
  let player: AVPlayer

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    let playerLayer = AVPlayerLayer(player: player)
    playerLayer.videoGravity = .resizeAspect
    view.wantsLayer = true
    view.layer = playerLayer
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    if let layer = nsView.layer as? AVPlayerLayer {
      layer.player = player
    }
  }
}
#else
import UIKit

struct VideoPlayerRepresentable: UIViewRepresentable {
  let player: AVPlayer

  func makeUIView(context: Context) -> UIView {
    let view = PlayerUIView()
    view.playerLayer.player = player
    view.playerLayer.videoGravity = .resizeAspect
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    if let view = uiView as? PlayerUIView {
      view.playerLayer.player = player
    }
  }
}

final class PlayerUIView: UIView {
  override class var layerClass: AnyClass { AVPlayerLayer.self }
  var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
#endif
