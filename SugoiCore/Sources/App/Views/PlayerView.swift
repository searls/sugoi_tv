import AVFoundation
import SwiftUI

/// Platform video player using AVPlayerLayer directly on all platforms.
/// Passes through all events to SwiftUI overlays (e.g. the channel guide button).
public struct PlayerView: View {
  let playerManager: PlayerManager

  public init(playerManager: PlayerManager) {
    self.playerManager = playerManager
  }

  public var body: some View {
    Group {
      if let player = playerManager.player {
        SystemPlayerView(player: player)
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
