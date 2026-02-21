import Foundation
import Testing

@testable import IPTVProvider

@Suite("M3UParser")
struct M3UParserTests {
  let fixtureContent: String

  init() throws {
    let url = Bundle.module.url(forResource: "sample", withExtension: "m3u", subdirectory: "Fixtures")!
    fixtureContent = try String(contentsOf: url, encoding: .utf8)
  }

  @Test("Parses correct number of channels (skips broken URLs)")
  func channelCount() {
    let result = M3UParser.parse(fixtureContent)
    #expect(result.channels.count == 4)
  }

  @Test("Extracts EPG URL from header")
  func epgURL() {
    let result = M3UParser.parse(fixtureContent)
    #expect(result.epgURL == URL(string: "http://example.com/epg.xml"))
  }

  @Test("Extracts tvg-id attribute")
  func tvgID() {
    let result = M3UParser.parse(fixtureContent)
    #expect(result.channels[0].id == "NHK.jp")
    #expect(result.channels[1].id == "TBS.jp")
  }

  @Test("Auto-generates ID when tvg-id is missing")
  func autoID() {
    let result = M3UParser.parse(fixtureContent)
    let noIDChannel = result.channels[3]
    #expect(noIDChannel.id == "auto-4")
  }

  @Test("Extracts display name from after comma")
  func displayName() {
    let result = M3UParser.parse(fixtureContent)
    #expect(result.channels[0].name == "NHK General TV")
    #expect(result.channels[1].name == "TBS Television")
  }

  @Test("Extracts logo URL")
  func logoURL() {
    let result = M3UParser.parse(fixtureContent)
    #expect(result.channels[0].logoURL == URL(string: "http://example.com/nhk.png"))
    #expect(result.channels[2].logoURL == nil)
  }

  @Test("Extracts group-title")
  func groupTitle() {
    let result = M3UParser.parse(fixtureContent)
    #expect(result.channels[0].group == "News")
    #expect(result.channels[1].group == "Entertainment")
  }

  @Test("Extracts tvg-chno")
  func channelNumber() {
    let result = M3UParser.parse(fixtureContent)
    #expect(result.channels[0].channelNumber == 1)
    #expect(result.channels[1].channelNumber == 6)
    #expect(result.channels[3].channelNumber == 10)
  }

  @Test("Auto-assigns sequential channel number when tvg-chno missing")
  func autoChannelNumber() {
    let result = M3UParser.parse(fixtureContent)
    // NTV has no tvg-chno, should get auto-number 3
    #expect(result.channels[2].channelNumber == 3)
  }

  @Test("Captures stream URLs")
  func streamURLs() {
    let result = M3UParser.parse(fixtureContent)
    #expect(result.channels[0].streamURL == URL(string: "http://example.com/stream/nhk.m3u8"))
    #expect(result.channels[1].streamURL == URL(string: "http://example.com/stream/tbs.m3u8"))
  }

  @Test("Empty content returns empty channels and nil EPG")
  func emptyContent() {
    let result = M3UParser.parse("")
    #expect(result.channels.isEmpty)
    #expect(result.epgURL == nil)
  }

  @Test("Header without EPG URL returns nil")
  func noEPGURL() {
    let result = M3UParser.parse("#EXTM3U\n#EXTINF:-1,Test\nhttp://test.com/stream.m3u8")
    #expect(result.epgURL == nil)
    #expect(result.channels.count == 1)
  }
}
