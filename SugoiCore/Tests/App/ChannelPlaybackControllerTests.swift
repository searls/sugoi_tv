import Foundation
import SwiftUI
import Testing

@testable import SugoiCore

@Suite("ChannelPlaybackController.loadAndAutoSelect")
@MainActor
struct ChannelPlaybackControllerAutoSelectTests {
  nonisolated static var testConfig: ProductConfig {
    ProductConfig(
      vmsHost: "http://live.yoitv.com:9083",
      vmsVodHost: nil, vmsUid: "UID", vmsLiveCid: "CID",
      vmsReferer: "http://play.yoitv.com", epgDays: nil, single: nil,
      vmsChannelListHost: nil, vmsLiveHost: nil, vmsRecordHost: nil, vmsLiveUid: nil
    )
  }

  @Test("Selects last-used channel when lastChannelId matches")
  func selectsLastChannel() async throws {
    let controller = try ControllerTestFixtures.makeController()
    controller.persistence.lastChannelId = "CH2"

    await controller.loadAndAutoSelect()

    #expect(controller.selectedChannel?.id == "CH2")
  }

  @Test("Falls back to first running channel when lastChannelId doesn't match")
  func selectsRunningChannel() async throws {
    let controller = try ControllerTestFixtures.makeController()
    controller.persistence.lastChannelId = "NONEXISTENT"

    await controller.loadAndAutoSelect()

    #expect(controller.selectedChannel?.id == "CH1", "CH1 is the only channel with running == 1")
  }

  @Test("Falls back to first channel when no channels are running")
  func selectsFirstChannel() async throws {
    let controller = try ControllerTestFixtures.makeController(channelsJSON: ControllerTestFixtures.allStoppedJSON)
    controller.persistence.lastChannelId = ""

    await controller.loadAndAutoSelect()

    #expect(controller.selectedChannel?.id == "CH1", "Should pick the first channel as last resort")
  }

  @Test("Selects first running channel when no lastChannelId is set")
  func selectsRunningWithNoHistory() async throws {
    let controller = try ControllerTestFixtures.makeController()
    controller.persistence.lastChannelId = ""

    await controller.loadAndAutoSelect()

    #expect(controller.selectedChannel?.id == "CH1")
  }

  @Test("Re-selects when previously selected channel disappears from fresh list")
  func reSelectsWhenChannelDisappears() async throws {
    let controller = try ControllerTestFixtures.makeController()
    // Pre-set a channel that won't exist in the fresh response
    controller.setSelectedChannelForTesting(ChannelDTO(
      id: "REMOVED", uid: nil, name: "Gone Channel", description: nil, tags: nil,
      no: 99, timeshift: nil, timeshiftLen: nil, epgKeepDays: nil, state: nil,
      running: nil, playpath: "/gone", liveType: nil
    ))
    controller.persistence.lastChannelId = ""

    await controller.loadAndAutoSelect()

    // Should have re-selected to a channel from the fresh list (CH1 = running)
    #expect(controller.selectedChannel?.id != "REMOVED")
    #expect(controller.selectedChannel?.id == "CH1")
  }
}

@Suite("ChannelPlaybackController.shouldCollapseSidebarOnTap")
@MainActor
struct ChannelPlaybackControllerSidebarCollapseTests {
  @Test("Allows sidebar collapse when external playback is inactive")
  func allowsCollapseByDefault() throws {
    let controller = try ControllerTestFixtures.makeController()

    #expect(controller.playerManager.isExternalPlaybackActive == false)
    #expect(controller.shouldCollapseSidebarOnTap == true)
  }

  @Test("Prevents sidebar collapse when AirPlay is active")
  func preventsCollapseDuringAirPlay() throws {
    let controller = try ControllerTestFixtures.makeController()
    // Simulate AirPlay becoming active (KVO would set this in production)
    controller.playerManager.setExternalPlaybackActiveForTesting(true)

    #expect(controller.shouldCollapseSidebarOnTap == false)
  }

  @Test("Re-allows sidebar collapse after AirPlay stops")
  func reallowsCollapseAfterAirPlayStops() throws {
    let controller = try ControllerTestFixtures.makeController()
    controller.playerManager.setExternalPlaybackActiveForTesting(true)
    #expect(controller.shouldCollapseSidebarOnTap == false)

    controller.playerManager.setExternalPlaybackActiveForTesting(false)
    #expect(controller.shouldCollapseSidebarOnTap == true)
  }
}

@Suite("ChannelPlaybackController.preferredCompactColumn")
@MainActor
struct ChannelPlaybackControllerCompactColumnTests {
  @Test("Starts on sidebar column for compact layouts")
  func startsOnSidebar() throws {
    let controller = try ControllerTestFixtures.makeController()
    #expect(controller.preferredCompactColumn == .sidebar)
  }

  @Test("Switches to detail column when playing a channel")
  func switchesToDetailOnPlay() async throws {
    let controller = try ControllerTestFixtures.makeController()
    #expect(controller.preferredCompactColumn == .sidebar)

    await controller.loadAndAutoSelect()
    // autoSelectChannel no longer auto-plays; explicitly play
    controller.playChannel(controller.selectedChannel!)

    #expect(controller.preferredCompactColumn == .detail)
  }
}

@Suite("ChannelPlaybackController.playVOD")
@MainActor
struct ChannelPlaybackControllerPlayVODTests {
  @Test("playVOD loads VOD stream and switches to detail column")
  func playVODLoadsStream() throws {
    let controller = try ControllerTestFixtures.makeController()
    let program = ProgramDTO(time: 1000, title: "Past Show", path: "/query/past_show")

    controller.playVOD(program: program, channelName: "NHK")

    #expect(controller.preferredCompactColumn == .detail)
    #expect(controller.playerManager.state != .idle)
  }

  @Test("playVOD does nothing when program has no VOD")
  func playVODNoOpWithoutVOD() throws {
    let controller = try ControllerTestFixtures.makeController()
    let program = ProgramDTO(time: 1000, title: "Live Only", path: "")

    controller.playVOD(program: program, channelName: "NHK")

    #expect(controller.preferredCompactColumn == .sidebar)
    #expect(controller.playerManager.state == .idle)
  }

  @Test("playVOD resets reauth flag")
  func playVODResetsReauth() throws {
    let controller = try ControllerTestFixtures.makeController()
    controller.setHasAttemptedReauthForTesting(true)
    let program = ProgramDTO(time: 1000, title: "Past Show", path: "/query/past_show")

    controller.playVOD(program: program, channelName: "NHK")

    #expect(controller.hasAttemptedReauth == false)
  }

  @Test("playVOD persists VOD program info")
  func playVODPersistsInfo() throws {
    let controller = try ControllerTestFixtures.makeController()
    let program = ProgramDTO(time: 1000, title: "Past Show", path: "/query/past_show")

    controller.playVOD(program: program, channelName: "NHK総合")

    #expect(controller.persistence.lastPlayingProgramID == "/query/past_show")
    #expect(controller.persistence.lastPlayingProgramTitle == "Past Show")
    #expect(controller.persistence.lastPlayingChannelName == "NHK総合")
  }

  @Test("playChannel clears VOD persistence")
  func playChannelClearsVODInfo() throws {
    let controller = try ControllerTestFixtures.makeController()
    let program = ProgramDTO(time: 1000, title: "Past Show", path: "/query/past_show")
    controller.playVOD(program: program, channelName: "NHK総合")

    let channel = ChannelDTO(
      id: "CH1", uid: nil, name: "NHK総合", description: nil, tags: nil,
      no: 1, timeshift: nil, timeshiftLen: nil, epgKeepDays: nil, state: nil,
      running: 1, playpath: "/query/s/nhk", liveType: nil
    )
    controller.playChannel(channel)

    #expect(controller.persistence.lastPlayingProgramID == "")
    #expect(controller.persistence.lastPlayingProgramTitle == "")
    #expect(controller.persistence.lastPlayingChannelName == "")
    #expect(controller.persistence.lastVODPosition == 0)
  }
}

@Suite("ChannelPlaybackController.replayCurrentStream")
@MainActor
struct ChannelPlaybackControllerReplayTests {
  @Test("Replays VOD when VOD was playing")
  func replaysVOD() throws {
    let controller = try ControllerTestFixtures.makeController()
    let program = ProgramDTO(time: 1000, title: "Past Show", path: "/query/past_show")
    controller.playVOD(program: program, channelName: "NHK総合")

    #expect(controller.playingProgramID == "/query/past_show")

    controller.replayCurrentStream()

    // Must still be VOD, not switched to live
    #expect(controller.playingProgramID == "/query/past_show")
    #expect(controller.persistence.lastPlayingProgramID == "/query/past_show")
    #expect(controller.persistence.lastPlayingProgramTitle == "Past Show")
    #expect(controller.persistence.lastPlayingChannelName == "NHK総合")
  }

  @Test("Replays live when live was playing via sidebarPath")
  func replaysLiveFromSidebarPath() throws {
    let controller = try ControllerTestFixtures.makeController()
    let channel = ChannelDTO(
      id: "CH1", uid: nil, name: "NHK総合", description: nil, tags: nil,
      no: 1, timeshift: nil, timeshiftLen: nil, epgKeepDays: nil, state: nil,
      running: 1, playpath: "/query/s/nhk", liveType: nil
    )
    controller.sidebarPath = [channel]
    controller.playChannel(channel)

    #expect(controller.playingProgramID == nil)

    controller.replayCurrentStream()

    #expect(controller.playingProgramID == nil)
    #expect(controller.persistence.lastPlayingProgramID == "")
  }

  @Test("Replays live using selectedChannel when sidebarPath is empty")
  func replaysLiveFromSelectedChannel() throws {
    let controller = try ControllerTestFixtures.makeController()
    let channel = ChannelDTO(
      id: "CH1", uid: nil, name: "NHK総合", description: nil, tags: nil,
      no: 1, timeshift: nil, timeshiftLen: nil, epgKeepDays: nil, state: nil,
      running: 1, playpath: "/query/s/nhk", liveType: nil
    )
    controller.setSelectedChannelForTesting(channel)
    controller.playChannel(channel)

    // sidebarPath is empty — playing live from channel list
    #expect(controller.sidebarPath.isEmpty)
    #expect(controller.playingProgramID == nil)

    controller.replayCurrentStream()

    // Should still replay via selectedChannel fallback
    #expect(controller.playerManager.state != .idle)
    #expect(controller.playingProgramID == nil)
  }

  @Test("Preserves persisted VOD position on replay")
  func preservesVODPosition() throws {
    let controller = try ControllerTestFixtures.makeController()
    let program = ProgramDTO(time: 1000, title: "Past Show", path: "/query/past_show")
    controller.playVOD(program: program, channelName: "NHK総合")
    controller.persistence.lastVODPosition = 300

    controller.replayCurrentStream()

    // VOD persistence intact — position not wiped
    #expect(controller.persistence.lastPlayingProgramID == "/query/past_show")
    #expect(controller.persistence.lastVODPosition != 0)
  }

  @Test("No-op when nothing is playing and no channel available")
  func noOpWhenNothingAvailable() throws {
    let controller = try ControllerTestFixtures.makeController()

    #expect(controller.playingProgramID == nil)
    #expect(controller.sidebarPath.isEmpty)
    #expect(controller.selectedChannel == nil)

    controller.replayCurrentStream()

    #expect(controller.playerManager.state == .idle)
  }
}

@Suite("ChannelPlaybackController.sidebarPath")
@MainActor
struct ChannelPlaybackControllerSidebarPathTests {
  @Test("sidebarPath starts empty")
  func startsEmpty() throws {
    let controller = try ControllerTestFixtures.makeController()
    #expect(controller.sidebarPath.isEmpty)
  }

  @Test("loadAndAutoSelect selects channel without drilling into program list")
  func autoSelectStaysOnChannelList() async throws {
    let controller = try ControllerTestFixtures.makeController()
    await controller.loadAndAutoSelect()

    #expect(controller.selectedChannel != nil)
    #expect(controller.sidebarPath.isEmpty)
  }

  @Test("programListViewModel creates and caches viewmodel for channel")
  func programListVM() async throws {
    let controller = try ControllerTestFixtures.makeController()
    await controller.loadAndAutoSelect()

    guard let channel = controller.selectedChannel else {
      Issue.record("No channel selected")
      return
    }

    let vm1 = controller.programListViewModel(for: channel)
    #expect(vm1.channelID == channel.id)
    #expect(vm1.channelName == channel.name)

    // Same channel returns same cached instance
    let vm2 = controller.programListViewModel(for: channel)
    #expect(vm1 === vm2)
  }
}

// MARK: - Proxy URL fallback

@Suite("ChannelPlaybackController.playChannel proxy fallback")
@MainActor
struct PlayChannelProxyFallbackTests {
  @Test("playChannel uses direct URL when no proxy is configured")
  func playChannelDirectFallback() throws {
    let controller = try ControllerTestFixtures.makeController()
    let channel = ChannelDTO(
      id: "CH1", uid: nil, name: "NHK総合", description: nil, tags: nil,
      no: 1, timeshift: nil, timeshiftLen: nil, epgKeepDays: nil, state: nil,
      running: 1, playpath: "/query/s/nhk", liveType: nil
    )

    // No proxy configured (provider doesn't require one) → uses direct URL
    #expect(controller.refererProxy == nil)
    controller.playChannel(channel)
    #expect(controller.playerManager.state != .idle)
  }

  @Test("playVOD uses direct URL when no proxy is configured")
  func playVODDirectFallback() throws {
    let controller = try ControllerTestFixtures.makeController()
    let program = ProgramDTO(time: 1000, title: "Past Show", path: "/query/past_show")

    #expect(controller.refererProxy == nil)
    controller.playVOD(program: program, channelName: "NHK")
    #expect(controller.playerManager.state != .idle)
  }
}
