import Foundation
import Testing

@testable import SugoiCore

@Suite("LaunchPlayback.decide")
struct LaunchPlaybackTests {
  let now: TimeInterval = 1_700_000_000 // arbitrary fixed time
  let recentTimestamp: TimeInterval = 1_700_000_000 - 3600 // 1 hour ago
  let staleTimestamp: TimeInterval = 1_700_000_000 - 13 * 3600 // 13 hours ago
  let exactThreshold: TimeInterval = 1_700_000_000 - 12 * 3600 // exactly 12 hours ago

  @Test("iPhone always returns doNothing")
  func iPhoneDoesNothing() {
    let result = LaunchPlayback.decide(
      isCompact: true,
      lastActiveTimestamp: recentTimestamp,
      now: now,
      lastProgramID: "/vod/show",
      lastProgramTitle: "Show",
      lastChannelName: "NHK",
      lastVODPosition: 120
    )
    #expect(result == .doNothing)
  }

  @Test("First launch returns playLive")
  func firstLaunchPlaysLive() {
    let result = LaunchPlayback.decide(
      isCompact: false,
      lastActiveTimestamp: 0,
      now: now,
      lastProgramID: "",
      lastProgramTitle: "",
      lastChannelName: "",
      lastVODPosition: 0
    )
    #expect(result == .playLive)
  }

  @Test("Stale session returns playLive")
  func staleSessionPlaysLive() {
    let result = LaunchPlayback.decide(
      isCompact: false,
      lastActiveTimestamp: staleTimestamp,
      now: now,
      lastProgramID: "/vod/show",
      lastProgramTitle: "Show",
      lastChannelName: "NHK",
      lastVODPosition: 120
    )
    #expect(result == .playLive)
  }

  @Test("Exactly at 12h threshold returns playLive")
  func exactThresholdPlaysLive() {
    let result = LaunchPlayback.decide(
      isCompact: false,
      lastActiveTimestamp: exactThreshold,
      now: now,
      lastProgramID: "/vod/show",
      lastProgramTitle: "Show",
      lastChannelName: "NHK",
      lastVODPosition: 120
    )
    #expect(result == .playLive)
  }

  @Test("Recent session with VOD returns resumeVOD")
  func recentWithVODResumes() {
    let result = LaunchPlayback.decide(
      isCompact: false,
      lastActiveTimestamp: recentTimestamp,
      now: now,
      lastProgramID: "/vod/show",
      lastProgramTitle: "Past Show",
      lastChannelName: "NHK総合",
      lastVODPosition: 300
    )
    #expect(result == .resumeVOD(
      programID: "/vod/show",
      title: "Past Show",
      channelName: "NHK総合",
      position: 300
    ))
  }

  @Test("Recent session without VOD returns playLive")
  func recentWithoutVODPlaysLive() {
    let result = LaunchPlayback.decide(
      isCompact: false,
      lastActiveTimestamp: recentTimestamp,
      now: now,
      lastProgramID: "",
      lastProgramTitle: "",
      lastChannelName: "",
      lastVODPosition: 0
    )
    #expect(result == .playLive)
  }
}
