import Foundation
import Testing

@testable import IPTVProvider
@testable import SugoiCore

@Suite("IPTVProvider")
struct IPTVProviderTests {
  let sampleM3U = """
    #EXTM3U x-tvg-url="http://example.com/epg.xml"
    #EXTINF:-1 tvg-id="NHK.jp" tvg-logo="http://example.com/nhk.png" group-title="News" tvg-chno="1",NHK General
    http://example.com/stream/nhk.m3u8
    #EXTINF:-1 tvg-id="TBS.jp" tvg-logo="http://example.com/tbs.png" group-title="Entertainment" tvg-chno="6",TBS
    http://example.com/stream/tbs.m3u8
    """

  let sampleXMLTV = """
    <?xml version="1.0" encoding="UTF-8"?>
    <tv>
      <programme start="20250101090000 +0900" stop="20250101100000 +0900" channel="NHK.jp">
        <title>Morning News</title>
      </programme>
    </tv>
    """.data(using: .utf8)!

  init() {
    // Clean up UserDefaults from previous test runs
    UserDefaults.standard.removeObject(forKey: "iptv_m3u_url")
  }

  @Test("login populates channels")
  func loginPopulatesChannels() async throws {
    let provider = IPTVProvider()
    provider.overrideM3UData = sampleM3U

    try await provider.login(credentials: ["m3u_url": "http://test.com/test.m3u"])

    let channels = try await provider.fetchChannels()
    #expect(channels.count == 2)
    #expect(channels[0].id == "NHK.jp")
    #expect(channels[0].name == "NHK General")
    #expect(channels[1].id == "TBS.jp")
  }

  @Test("fetchChannels returns correct DTOs with tags")
  func fetchChannelsDTO() async throws {
    let provider = IPTVProvider()
    provider.overrideM3UData = sampleM3U
    try await provider.login(credentials: ["m3u_url": "http://test.com/test.m3u"])

    let channels = try await provider.fetchChannels()

    #expect(channels[0].tags == "$LIVE_CAT_News")
    #expect(channels[0].no == 1)
    #expect(channels[1].tags == "$LIVE_CAT_Entertainment")
    #expect(channels[1].no == 6)
  }

  @Test("thumbnailURL returns logo URLs")
  func thumbnailURL() async throws {
    let provider = IPTVProvider()
    provider.overrideM3UData = sampleM3U
    try await provider.login(credentials: ["m3u_url": "http://test.com/test.m3u"])

    let channels = try await provider.fetchChannels()
    let thumbURL = provider.thumbnailURL(for: channels[0])
    #expect(thumbURL == URL(string: "http://example.com/nhk.png"))
  }

  @Test("liveStreamRequest returns direct URL with no headers")
  func liveStreamRequest() async throws {
    let provider = IPTVProvider()
    provider.overrideM3UData = sampleM3U
    try await provider.login(credentials: ["m3u_url": "http://test.com/test.m3u"])

    let channels = try await provider.fetchChannels()
    let request = provider.liveStreamRequest(for: channels[0])
    #expect(request != nil)
    #expect(request?.url == URL(string: "http://example.com/stream/nhk.m3u8"))
    #expect(request?.headers.isEmpty == true)
    #expect(request?.requiresProxy == false)
  }

  @Test("vodStreamRequest always returns nil")
  func vodStreamRequestNil() async throws {
    let provider = IPTVProvider()
    let program = ProgramDTO(time: 1000, title: "Test")
    #expect(provider.vodStreamRequest(for: program) == nil)
  }

  @Test("restoreSession round-trips through UserDefaults")
  func restoreSession() async throws {
    let provider = IPTVProvider()
    provider.overrideM3UData = sampleM3U
    try await provider.login(credentials: ["m3u_url": "http://test.com/test.m3u"])

    // Create a new provider instance that reads from UserDefaults
    let provider2 = IPTVProvider()
    provider2.overrideM3UData = sampleM3U
    let restored = try await provider2.restoreSession()
    #expect(restored == true)

    let channels = try await provider2.fetchChannels()
    #expect(channels.count == 2)
  }

  @Test("restoreSession returns false when no saved URL")
  func restoreSessionNoURL() async throws {
    let provider = IPTVProvider()
    let restored = try await provider.restoreSession()
    #expect(restored == false)
  }

  @Test("logout clears state and UserDefaults")
  func logout() async throws {
    let provider = IPTVProvider()
    provider.overrideM3UData = sampleM3U
    try await provider.login(credentials: ["m3u_url": "http://test.com/test.m3u"])
    #expect(await provider.isAuthenticated == true)

    await provider.logout()

    #expect(await provider.isAuthenticated == false)
    #expect(UserDefaults.standard.string(forKey: "iptv_m3u_url") == nil)
  }

  @Test("isAuthenticated is false before login")
  func notAuthenticatedInitially() async {
    let provider = IPTVProvider()
    #expect(await provider.isAuthenticated == false)
  }

  @Test("loginFields contains M3U URL field with default")
  func loginFieldsStructure() {
    let provider = IPTVProvider()
    #expect(provider.loginFields.count == 1)
    #expect(provider.loginFields[0].key == "m3u_url")
    #expect(provider.loginFields[0].contentType == .url)
    #expect(provider.loginFields[0].defaultValue == IPTVProvider.defaultM3UURL)
  }

  @Test("fetchPrograms returns EPG data converted to ProgramDTO")
  func fetchPrograms() async throws {
    let provider = IPTVProvider()
    provider.overrideM3UData = sampleM3U
    provider.overrideEPGData = sampleXMLTV
    try await provider.login(credentials: ["m3u_url": "http://test.com/test.m3u"])

    let programs = try await provider.fetchPrograms(channelID: "NHK.jp")
    #expect(programs.count == 1)
    #expect(programs[0].title == "Morning News")
    #expect(programs[0].path == "")
    #expect(programs[0].hasVOD == false)
  }

  @Test("groupByCategory uses alphabetical order")
  func groupByCategory() async throws {
    let provider = IPTVProvider()
    provider.overrideM3UData = sampleM3U
    try await provider.login(credentials: ["m3u_url": "http://test.com/test.m3u"])

    let channels = try await provider.fetchChannels()
    let groups = provider.groupByCategory(channels)

    #expect(groups.count == 2)
    // Alphabetical: Entertainment before News
    #expect(groups[0].category == "Entertainment")
    #expect(groups[1].category == "News")
  }
}
