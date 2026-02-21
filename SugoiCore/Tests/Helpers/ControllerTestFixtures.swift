import Foundation

@testable import SugoiCore

/// Shared test fixtures for ChannelPlaybackController test suites.
/// Eliminates duplication of makeController() and JSON fixtures across 7 suites.
enum ControllerTestFixtures {
  static let testChannels: [ChannelDTO] = {
    let json = Data(channelsJSON.utf8)
    let response = try! JSONDecoder().decode(ChannelListResponse.self, from: json)
    return response.result
  }()

  static let allStoppedChannels: [ChannelDTO] = {
    let json = Data(allStoppedJSON.utf8)
    let response = try! JSONDecoder().decode(ChannelListResponse.self, from: json)
    return response.result
  }()

  // Two categories, one channel running, to exercise all selection paths
  static let channelsJSON = """
    {
      "result": [
        {"id": "CH1", "name": "NHK総合", "tags": "$LIVE_CAT_関東", "no": 1, "playpath": "/nhk", "running": 1},
        {"id": "CH2", "name": "テレビ朝日", "tags": "$LIVE_CAT_関東", "no": 2, "playpath": "/tvasahi"},
        {"id": "CH3", "name": "MBS毎日放送", "tags": "$LIVE_CAT_関西", "no": 3, "playpath": "/mbs"}
      ],
      "code": "OK"
    }
    """

  // All channels stopped — no running == 1
  static let allStoppedJSON = """
    {
      "result": [
        {"id": "CH1", "name": "NHK総合", "tags": "$LIVE_CAT_関東", "no": 1, "playpath": "/nhk"},
        {"id": "CH2", "name": "テレビ朝日", "tags": "$LIVE_CAT_関東", "no": 2, "playpath": "/tvasahi"}
      ],
      "code": "OK"
    }
    """

  @MainActor
  static func makeController(channels: [ChannelDTO]? = nil) throws -> ChannelPlaybackController {
    let mock = MockTVProvider(
      isAuthenticated: true,
      channels: channels ?? testChannels
    )
    mock.setLiveStreamHandler { channel in
      StreamRequest(
        url: URL(string: "http://test.com\(channel.playpath).M3U8?type=live")!,
        headers: ["Referer": "http://play.yoitv.com"],
        requiresProxy: false
      )
    }
    mock.setVODStreamHandler { program in
      guard program.hasVOD else { return nil }
      return StreamRequest(
        url: URL(string: "http://test.com\(program.path).m3u8?type=vod")!,
        headers: ["Referer": "http://play.yoitv.com"],
        requiresProxy: false
      )
    }

    let appState = AppState(provider: mock)
    return ChannelPlaybackController(appState: appState)
  }

  @MainActor
  static func makeController(channelsJSON: String) throws -> ChannelPlaybackController {
    let json = Data(channelsJSON.utf8)
    let response = try JSONDecoder().decode(ChannelListResponse.self, from: json)
    return try makeController(channels: response.result)
  }
}
