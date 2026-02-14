import AVFoundation
import AVKit
import SwiftUI

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

#elseif os(iOS)
import UIKit

// MARK: UIView backed by AVPlayerLayer

/// UIView backed by AVPlayerLayer with black background for letterbox bars.
/// Returns nil from hitTest so touch events pass through to SwiftUI controls.
class PassthroughPlayerUIView: UIView {
  override class var layerClass: AnyClass { AVPlayerLayer.self }

  var playerLayer: AVPlayerLayer {
    layer as! AVPlayerLayer
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .black
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    nil
  }
}

/// Renders video via AVPlayerLayer with event passthrough.
/// Optionally vends an AVPictureInPictureController via binding.
struct PassthroughPlayerView: UIViewRepresentable {
  let player: AVPlayer
  var pipController: Binding<AVPictureInPictureController?>? = nil

  static func makeConfiguredView(player: AVPlayer) -> PassthroughPlayerUIView {
    let view = PassthroughPlayerUIView()
    view.playerLayer.player = player
    view.playerLayer.videoGravity = .resizeAspect
    return view
  }

  func makeUIView(context: Context) -> PassthroughPlayerUIView {
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

  func updateUIView(_ uiView: PassthroughPlayerUIView, context: Context) {
    if uiView.playerLayer.player !== player {
      uiView.playerLayer.player = player
    }
  }
}
#endif
