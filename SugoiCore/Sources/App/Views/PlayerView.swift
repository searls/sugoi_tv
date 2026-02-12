import AVFoundation
import SwiftUI

/// Platform video player using AVPlayerLayer directly on all platforms.
/// Passes through all events to SwiftUI overlays (e.g. the channel guide button).
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
    .accessibilityIdentifier("playerView")
  }
}

// MARK: - Platform system player wrappers

#if os(macOS)
import AppKit

/// Renders video via AVPlayerLayer but returns nil from hitTest so all mouse
/// events pass through to SwiftUI overlays (e.g. the channel guide button).
/// AVPlayerView intercepts events at the AppKit level even when SwiftUI's
/// .allowsHitTesting(false) is applied, so we bypass it entirely.
private class PassthroughPlayerNSView: NSView {
  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func makeBackingLayer() -> CALayer {
    AVPlayerLayer()
  }

  var playerLayer: AVPlayerLayer {
    layer as! AVPlayerLayer
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }
}

private struct SystemPlayerView: NSViewRepresentable {
  let player: AVPlayer
  let isLive: Bool

  func makeNSView(context: Context) -> PassthroughPlayerNSView {
    let view = PassthroughPlayerNSView()
    view.playerLayer.player = player
    view.playerLayer.videoGravity = .resizeAspect
    return view
  }

  func updateNSView(_ nsView: PassthroughPlayerNSView, context: Context) {
    if nsView.playerLayer.player !== player {
      nsView.playerLayer.player = player
    }
  }
}

#else
import UIKit

/// Renders video via AVPlayerLayer with user interaction disabled so all touches
/// pass through to SwiftUI overlays. AVPlayerViewController intercepts gestures
/// at the UIKit level even with SwiftUI's .allowsHitTesting(false).
private class PassthroughPlayerUIView: UIView {
  override class var layerClass: AnyClass { AVPlayerLayer.self }

  var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    nil
  }
}

private struct SystemPlayerView: UIViewRepresentable {
  let player: AVPlayer
  let isLive: Bool

  func makeUIView(context: Context) -> PassthroughPlayerUIView {
    let view = PassthroughPlayerUIView()
    view.playerLayer.player = player
    view.playerLayer.videoGravity = .resizeAspect
    return view
  }

  func updateUIView(_ uiView: PassthroughPlayerUIView, context: Context) {
    if uiView.playerLayer.player !== player {
      uiView.playerLayer.player = player
    }
  }
}
#endif
