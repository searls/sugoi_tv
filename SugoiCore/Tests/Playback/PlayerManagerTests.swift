import Foundation
import Testing

@testable import SugoiCore

@Suite("PlayerManager")
struct PlayerManagerTests {
  @Test("Initial state is idle")
  @MainActor
  func initialState() {
    let manager = PlayerManager()
    #expect(manager.state == .idle)
    #expect(manager.currentTime == 0)
    #expect(manager.duration == 0)
    #expect(manager.isLive == false)
    #expect(manager.isExternalPlaybackActive == false)
    #expect(manager.player == nil)
  }

  @Test("Loading live stream sets state to loading and isLive to true")
  @MainActor
  func loadLiveStream() {
    let manager = PlayerManager()
    let url = URL(string: "http://live.yoitv.com:9083/query/s/test.M3U8?type=live")!

    manager.loadLiveStream(url: url, referer: "http://play.yoitv.com")

    #expect(manager.state == .loading)
    #expect(manager.isLive == true)
    #expect(manager.player != nil)
  }

  @Test("Loading VOD stream sets state to loading and isLive to false")
  @MainActor
  func loadVODStream() {
    let manager = PlayerManager()
    let url = URL(string: "http://vod.yoitv.com:9083/query/test.m3u8?type=vod")!

    manager.loadVODStream(url: url, referer: "http://play.yoitv.com")

    #expect(manager.state == .loading)
    #expect(manager.isLive == false)
    #expect(manager.player != nil)
  }

  @Test("Stop resets to idle state")
  @MainActor
  func stopResetsState() {
    let manager = PlayerManager()
    let url = URL(string: "http://test.com/stream.m3u8")!

    manager.loadVODStream(url: url, referer: "http://play.yoitv.com")

    manager.stop()

    #expect(manager.state == .idle)
    #expect(manager.player == nil)
    #expect(manager.currentTime == 0)
    #expect(manager.duration == 0)
    #expect(manager.isLive == false)
    #expect(manager.isExternalPlaybackActive == false)
  }

  @Test("Play and pause toggle state when player exists")
  @MainActor
  func playPauseWithPlayer() {
    let manager = PlayerManager()
    let url = URL(string: "http://test.com/stream.m3u8")!
    manager.loadVODStream(url: url, referer: "http://play.yoitv.com")

    manager.play()
    #expect(manager.state == .playing)

    manager.pause()
    #expect(manager.state == .paused)
  }

  @Test("Toggle play/pause switches between states")
  @MainActor
  func togglePlayPause() {
    let manager = PlayerManager()
    let url = URL(string: "http://test.com/stream.m3u8")!
    manager.loadVODStream(url: url, referer: "http://play.yoitv.com")

    manager.play()
    #expect(manager.state == .playing)

    manager.togglePlayPause()
    #expect(manager.state == .paused)

    manager.togglePlayPause()
    #expect(manager.state == .playing)
  }

  @Test("Seek is ignored for live streams")
  @MainActor
  func seekIgnoredForLive() {
    let manager = PlayerManager()
    let url = URL(string: "http://test.com/stream.M3U8")!
    manager.loadLiveStream(url: url, referer: "http://play.yoitv.com")

    // Should not crash — seek is a no-op for live
    manager.seek(to: 30)
    manager.skipForward()
    manager.skipBackward()
  }

  @Test("Skip backward clamps to zero")
  @MainActor
  func skipBackwardClampsToZero() {
    let manager = PlayerManager()
    let url = URL(string: "http://test.com/stream.m3u8")!
    manager.loadVODStream(url: url, referer: "http://play.yoitv.com")
    // currentTime is 0, skipping backward 15s should seek to 0 not -15
    manager.skipBackward()
    // No crash means success — seek(to: 0) was called
  }

  @Test("Loading a new stream cleans up the previous one")
  @MainActor
  func loadingCleansUpPrevious() {
    let manager = PlayerManager()
    let url1 = URL(string: "http://test.com/stream1.m3u8")!
    let url2 = URL(string: "http://test.com/stream2.m3u8")!

    manager.loadVODStream(url: url1, referer: "http://play.yoitv.com")
    let firstPlayer = manager.player

    manager.loadLiveStream(url: url2, referer: "http://play.yoitv.com")
    let secondPlayer = manager.player

    #expect(firstPlayer !== secondPlayer)
    #expect(manager.isLive == true)
    #expect(manager.state == .loading)
    #expect(manager.isExternalPlaybackActive == false)
  }

  @Test("clearError resets failed state to idle")
  @MainActor
  func clearErrorFromFailed() {
    let manager = PlayerManager()
    manager.state = .failed("Stream error")

    manager.clearError()

    #expect(manager.state == .idle)
  }

  @Test("clearError is a no-op for non-failed states")
  @MainActor
  func clearErrorNoOpWhenPlaying() {
    let manager = PlayerManager()
    let url = URL(string: "http://test.com/stream.m3u8")!
    manager.loadVODStream(url: url, referer: "http://play.yoitv.com")
    manager.play()

    manager.clearError()

    #expect(manager.state == .playing)
  }

  @Test("retry re-creates player when state is failed")
  @MainActor
  func retryReCreatesPlayer() {
    let manager = PlayerManager()
    let url = URL(string: "http://test.com/stream.m3u8")!
    manager.loadLiveStream(url: url, referer: "http://play.yoitv.com")
    let firstPlayer = manager.player

    manager.state = .failed("Network error")
    manager.retry()

    #expect(manager.state == .loading)
    #expect(manager.player !== firstPlayer, "retry should create a new player")
    #expect(manager.player != nil)
  }

  @Test("retry is a no-op when not in failed state")
  @MainActor
  func retryNoOpWhenNotFailed() {
    let manager = PlayerManager()
    let url = URL(string: "http://test.com/stream.m3u8")!
    manager.loadLiveStream(url: url, referer: "http://play.yoitv.com")
    let player = manager.player

    manager.retry()

    #expect(manager.player === player, "retry should not touch a non-failed player")
  }

  @Test("retry is a no-op when no stream has been loaded")
  @MainActor
  func retryNoOpWithoutStream() {
    let manager = PlayerManager()
    manager.state = .failed("Error")

    manager.retry()

    // No lastStreamInfo, so retry should be a no-op
    #expect(manager.player == nil)
  }
}
