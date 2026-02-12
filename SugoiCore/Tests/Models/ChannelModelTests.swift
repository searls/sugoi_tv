import Foundation
import Testing

@testable import SugoiCore

@Suite("Channel model")
struct ChannelModelTests {
  @Test("Initializes from ChannelDTO")
  func initFromDTO() {
    let dto = ChannelDTO(
      id: "AA6EC2B2BC19EFE5FA44BE23187CDA63",
      uid: "C2D9261F3D5753E74E97EB28FE2D8B26",
      name: "NHK総合・東京",
      description: "[HD]NHK General",
      tags: "$LIVE_CAT_関東",
      no: 101024,
      timeshift: 1,
      timeshiftLen: 900,
      epgKeepDays: 28,
      state: 2,
      running: 1,
      playpath: "/query/s/Hqm-m7jqkFlA1CloJoaJZQ==",
      liveType: "video"
    )
    let channel = Channel(from: dto)

    #expect(channel.channelID == "AA6EC2B2BC19EFE5FA44BE23187CDA63")
    #expect(channel.name == "NHK総合・東京")
    #expect(channel.channelDescription == "[HD]NHK General")
    #expect(channel.tags == "$LIVE_CAT_関東")
    #expect(channel.playpath == "/query/s/Hqm-m7jqkFlA1CloJoaJZQ==")
    #expect(channel.no == 101024)
    #expect(channel.isRunning == true)
    #expect(channel.supportsTimeshift == true)
    #expect(channel.timeshiftLen == 900)
    #expect(channel.epgKeepDays == 28)
    #expect(channel.state == 2)
    #expect(channel.liveType == "video")
  }

  @Test("Category parsing from tags")
  func categoryParsing() {
    let channel = Channel()
    channel.tags = "$LIVE_CAT_関東"
    #expect(channel.categories == ["関東"])
    #expect(channel.primaryCategory == "関東")

    channel.tags = "$LIVE_CAT_関西, $LIVE_CAT_BS"
    #expect(channel.categories == ["関西", "BS"])
    #expect(channel.primaryCategory == "関西")

    channel.tags = ""
    #expect(channel.categories.isEmpty)
    #expect(channel.primaryCategory == "Others")
  }

  @Test("Thumbnail URL construction")
  func thumbnailURL() {
    let channel = Channel()
    channel.playpath = "/query/s/Hqm-m7jqkFlA1CloJoaJZQ=="
    let url = channel.thumbnailURL(host: "http://live.yoitv.com:9083")
    #expect(url?.absoluteString == "http://live.yoitv.com:9083/query/s/Hqm-m7jqkFlA1CloJoaJZQ==.jpg?type=live&thumbnail=thumbnail_small.jpg")
  }

  @Test("Update from DTO preserves channelID")
  func updateFromDTO() {
    let channel = Channel()
    channel.channelID = "ORIGINAL_ID"
    let dto = ChannelDTO(
      id: "DIFFERENT_ID", uid: nil, name: "Updated",
      description: nil, tags: nil, no: 5, timeshift: nil,
      timeshiftLen: nil, epgKeepDays: nil, state: nil,
      running: 0, playpath: "/new", liveType: nil
    )
    channel.update(from: dto)

    #expect(channel.channelID == "ORIGINAL_ID")
    #expect(channel.name == "Updated")
    #expect(channel.isRunning == false)
  }
}
