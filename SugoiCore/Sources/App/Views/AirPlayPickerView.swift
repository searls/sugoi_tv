import AVFoundation
import AVKit
import SwiftUI

#if os(macOS)
import AppKit

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

#elseif os(iOS)
import UIKit

/// Wraps AVRoutePickerView for AirPlay output selection on iOS.
/// Note: AVRoutePickerView.player is macOS-only; on iOS the picker
/// discovers routes automatically without a player reference.
struct AirPlayPickerView: UIViewRepresentable {
  let player: AVPlayer
  var onPresentingRoutesChanged: ((Bool) -> Void)? = nil

  static func makeConfiguredView() -> AVRoutePickerView {
    AVRoutePickerView()
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(onPresentingRoutesChanged: onPresentingRoutesChanged)
  }

  func makeUIView(context: Context) -> AVRoutePickerView {
    let picker = Self.makeConfiguredView()
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
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
#endif
