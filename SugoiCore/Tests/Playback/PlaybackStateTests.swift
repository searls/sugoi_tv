import Foundation
import Testing

@testable import SugoiCore

@Suite("PlaybackState")
struct PlaybackStateTests {
  @Test("PlaybackState equality")
  func equality() {
    #expect(PlaybackState.idle == PlaybackState.idle)
    #expect(PlaybackState.loading == PlaybackState.loading)
    #expect(PlaybackState.playing == PlaybackState.playing)
    #expect(PlaybackState.paused == PlaybackState.paused)
    #expect(PlaybackState.ended == PlaybackState.ended)
    #expect(PlaybackState.failed("error") == PlaybackState.failed("error"))
    #expect(PlaybackState.failed("a") != PlaybackState.failed("b"))
    #expect(PlaybackState.playing != PlaybackState.paused)
  }

  @Test("PlaybackState is Sendable")
  func sendable() async {
    let state: PlaybackState = .playing
    let task = Task { state }
    let result = await task.value
    #expect(result == .playing)
  }
}
