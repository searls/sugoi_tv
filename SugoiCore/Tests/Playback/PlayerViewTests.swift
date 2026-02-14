import AVFoundation
import Testing

@testable import SugoiCore

// MARK: - macOS: PassthroughPlayerView + AirPlayPickerView tests

#if os(macOS)
import AVKit

@Suite("PassthroughPlayerView (macOS)")
struct PassthroughPlayerViewTests {
  @Test("player layer is connected to player")
  @MainActor
  func playerLayerConnected() {
    let player = AVPlayer()
    let nsView = PassthroughPlayerView.makeConfiguredView(player: player)

    #expect(nsView.playerLayer.player === player)
  }

  @Test("video gravity is resizeAspect")
  @MainActor
  func videoGravityIsAspect() {
    let player = AVPlayer()
    let nsView = PassthroughPlayerView.makeConfiguredView(player: player)

    #expect(nsView.playerLayer.videoGravity == .resizeAspect)
  }

  @Test("hitTest returns nil for event passthrough")
  @MainActor
  func hitTestReturnsNil() {
    let player = AVPlayer()
    let nsView = PassthroughPlayerView.makeConfiguredView(player: player)
    nsView.frame = NSRect(x: 0, y: 0, width: 100, height: 100)

    #expect(nsView.hitTest(NSPoint(x: 50, y: 50)) == nil)
  }

  @Test("layer background is black for letterbox bars")
  @MainActor
  func layerBackgroundIsBlack() {
    let player = AVPlayer()
    let nsView = PassthroughPlayerView.makeConfiguredView(player: player)

    #expect(nsView.playerLayer.backgroundColor == NSColor.black.cgColor)
  }
}

@Suite("AirPlayPickerView (macOS)")
struct AirPlayPickerViewTests {
  @Test("player property is set on picker")
  @MainActor
  func playerIsSet() {
    let player = AVPlayer()
    let picker = AirPlayPickerView.makeConfiguredView(player: player)

    #expect(picker.player === player)
  }

  @Test("button is not bordered")
  @MainActor
  func buttonIsNotBordered() {
    let player = AVPlayer()
    let picker = AirPlayPickerView.makeConfiguredView(player: player)

    #expect(picker.isRoutePickerButtonBordered == false)
  }

  @Test("coordinator calls closure with true on willBeginPresentingRoutes")
  @MainActor
  func coordinatorCallsTrueOnBegin() {
    var captured: Bool?
    let coordinator = AirPlayPickerView.Coordinator(
      onPresentingRoutesChanged: { captured = $0 }
    )

    coordinator.routePickerViewWillBeginPresentingRoutes(AVRoutePickerView())

    #expect(captured == true)
  }

  @Test("coordinator calls closure with false on didEndPresentingRoutes")
  @MainActor
  func coordinatorCallsFalseOnEnd() {
    var captured: Bool?
    let coordinator = AirPlayPickerView.Coordinator(
      onPresentingRoutesChanged: { captured = $0 }
    )

    coordinator.routePickerViewDidEndPresentingRoutes(AVRoutePickerView())

    #expect(captured == false)
  }

  @Test("coordinator with nil closure does not crash")
  @MainActor
  func coordinatorNilClosureNoCrash() {
    let coordinator = AirPlayPickerView.Coordinator(
      onPresentingRoutesChanged: nil
    )

    coordinator.routePickerViewWillBeginPresentingRoutes(AVRoutePickerView())
    coordinator.routePickerViewDidEndPresentingRoutes(AVRoutePickerView())
  }
}

#elseif os(iOS)
import AVKit

@Suite("PassthroughPlayerView (iOS)")
struct PassthroughPlayerViewTests {
  @Test("player layer is connected to player")
  @MainActor
  func playerLayerConnected() {
    let player = AVPlayer()
    let uiView = PassthroughPlayerView.makeConfiguredView(player: player)

    #expect(uiView.playerLayer.player === player)
  }

  @Test("video gravity is resizeAspect")
  @MainActor
  func videoGravityIsAspect() {
    let player = AVPlayer()
    let uiView = PassthroughPlayerView.makeConfiguredView(player: player)

    #expect(uiView.playerLayer.videoGravity == .resizeAspect)
  }

  @Test("hitTest returns nil for event passthrough")
  @MainActor
  func hitTestReturnsNil() {
    let player = AVPlayer()
    let uiView = PassthroughPlayerView.makeConfiguredView(player: player)
    uiView.frame = CGRect(x: 0, y: 0, width: 100, height: 100)

    #expect(uiView.hitTest(CGPoint(x: 50, y: 50), with: nil) == nil)
  }

  @Test("layer class is AVPlayerLayer")
  @MainActor
  func layerClassIsAVPlayerLayer() {
    #expect(PassthroughPlayerUIView.layerClass == AVPlayerLayer.self)
  }

  @Test("background is black for letterbox bars")
  @MainActor
  func backgroundIsBlack() {
    let player = AVPlayer()
    let uiView = PassthroughPlayerView.makeConfiguredView(player: player)

    #expect(uiView.backgroundColor == .black)
  }
}

@Suite("AirPlayPickerView (iOS)")
struct AirPlayPickerViewTests {
  @Test("creates picker view")
  @MainActor
  func createsPickerView() {
    let picker = AirPlayPickerView.makeConfiguredView()

    #expect(picker is AVRoutePickerView)
  }

  @Test("coordinator calls closure with true on willBeginPresentingRoutes")
  @MainActor
  func coordinatorCallsTrueOnBegin() {
    var captured: Bool?
    let coordinator = AirPlayPickerView.Coordinator(
      onPresentingRoutesChanged: { captured = $0 }
    )

    coordinator.routePickerViewWillBeginPresentingRoutes(AVRoutePickerView())

    #expect(captured == true)
  }

  @Test("coordinator calls closure with false on didEndPresentingRoutes")
  @MainActor
  func coordinatorCallsFalseOnEnd() {
    var captured: Bool?
    let coordinator = AirPlayPickerView.Coordinator(
      onPresentingRoutesChanged: { captured = $0 }
    )

    coordinator.routePickerViewDidEndPresentingRoutes(AVRoutePickerView())

    #expect(captured == false)
  }

  @Test("coordinator with nil closure does not crash")
  @MainActor
  func coordinatorNilClosureNoCrash() {
    let coordinator = AirPlayPickerView.Coordinator(
      onPresentingRoutesChanged: nil
    )

    coordinator.routePickerViewWillBeginPresentingRoutes(AVRoutePickerView())
    coordinator.routePickerViewDidEndPresentingRoutes(AVRoutePickerView())
  }
}
#endif

// MARK: - Cross-platform: PlayerManager with video fixture

@Suite("PlayerManager video fixture")
struct PlayerManagerVideoFixtureTests {
  @Test("loads local video file and creates player")
  @MainActor
  func loadsLocalVideoFixture() throws {
    guard let url = Bundle.module.url(
      forResource: "test-video",
      withExtension: "mp4",
      subdirectory: "Fixtures"
    ) else {
      throw FixtureError.fileNotFound("test-video.mp4")
    }

    let manager = PlayerManager()
    manager.loadVODStream(url: url, referer: "http://test.local")

    #expect(manager.player != nil)
    #expect(manager.state == .loading)
    #expect(manager.isLive == false)
  }
}
