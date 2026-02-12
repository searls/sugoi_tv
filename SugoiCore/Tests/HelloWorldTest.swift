import Foundation
import Testing

@testable import SugoiCore

// MARK: - LoginResponse Tests

@Suite("LoginResponse")
struct LoginResponseTests {
  static let loginJSON = """
    {
      "access_token": "ZZVWXJbbTestToken==",
      "token_type": "bearer",
      "expires_in": 1770770216,
      "refresh_token": "HegSNmRefreshToken==",
      "expired": false,
      "disabled": false,
      "confirmed": true,
      "cid": "AABC538835997",
      "type": "tvum_cid",
      "trial": 0,
      "create_time": 1652403783,
      "expire_time": 1782959503,
      "product_config": "{\\"vms_host\\":\\"http://live.yoitv.com:9083\\",\\"vms_vod_host\\":\\"http://vod.yoitv.com:9083\\",\\"vms_uid\\":\\"C2D9261F3D5753E74E97EB28FE2D8B26\\",\\"vms_live_cid\\":\\"A1B9470C288260372598FC7C577E4C61\\",\\"vms_referer\\":\\"http://play.yoitv.com\\",\\"epg_days\\":30,\\"single\\":\\"https://crm.yoitv.com/single.sjs\\"}",
      "server_time": 1770755816,
      "code": "OK"
    }
    """

  @Test("Decodes login response from JSON")
  func decodesLoginResponse() throws {
    let data = Self.loginJSON.data(using: .utf8)!
    let response = try JSONDecoder().decode(LoginResponse.self, from: data)

    #expect(response.accessToken == "ZZVWXJbbTestToken==")
    #expect(response.refreshToken == "HegSNmRefreshToken==")
    #expect(response.cid == "AABC538835997")
    #expect(response.code == "OK")
    #expect(response.expired == false)
    #expect(response.confirmed == true)
    #expect(response.expiresIn == 1770770216)
    #expect(response.serverTime == 1770755816)
    #expect(response.expireTime == 1782959503)
  }

  @Test("Parses double-encoded product_config")
  func parsesProductConfig() throws {
    let data = Self.loginJSON.data(using: .utf8)!
    let response = try JSONDecoder().decode(LoginResponse.self, from: data)
    let config = try response.parseProductConfig()

    #expect(config.vmsHost == "http://live.yoitv.com:9083")
    #expect(config.vmsVodHost == "http://vod.yoitv.com:9083")
    #expect(config.vmsUid == "C2D9261F3D5753E74E97EB28FE2D8B26")
    #expect(config.vmsLiveCid == "A1B9470C288260372598FC7C577E4C61")
    #expect(config.vmsReferer == "http://play.yoitv.com")
    #expect(config.epgDays == 30)
    #expect(config.single == "https://crm.yoitv.com/single.sjs")
  }
}

// MARK: - ProductConfig Host Resolution Tests

@Suite("ProductConfig host resolution")
struct ProductConfigTests {
  @Test("Falls back to vmsHost when override hosts are nil")
  func fallbackHosts() {
    let config = ProductConfig(
      vmsHost: "http://live.yoitv.com:9083",
      vmsVodHost: nil,
      vmsUid: "UID",
      vmsLiveCid: "CID",
      vmsReferer: "http://play.yoitv.com",
      epgDays: 30,
      single: nil,
      vmsChannelListHost: nil,
      vmsLiveHost: nil,
      vmsRecordHost: nil,
      vmsLiveUid: nil
    )

    #expect(config.channelListHost == "http://live.yoitv.com:9083")
    #expect(config.liveHost == "http://live.yoitv.com:9083")
    #expect(config.vodHost == "http://live.yoitv.com:9083")
    #expect(config.recordHost == "http://live.yoitv.com:9083")
    #expect(config.liveUid == "UID")
  }

  @Test("Uses override hosts when provided")
  func overrideHosts() {
    let config = ProductConfig(
      vmsHost: "http://live.yoitv.com:9083",
      vmsVodHost: "http://vod.yoitv.com:9083",
      vmsUid: "UID",
      vmsLiveCid: "CID",
      vmsReferer: "http://play.yoitv.com",
      epgDays: 30,
      single: nil,
      vmsChannelListHost: "http://channels.yoitv.com:9083",
      vmsLiveHost: "http://live-alt.yoitv.com:9083",
      vmsRecordHost: "http://record.yoitv.com:9083",
      vmsLiveUid: "LIVE_UID"
    )

    #expect(config.channelListHost == "http://channels.yoitv.com:9083")
    #expect(config.liveHost == "http://live-alt.yoitv.com:9083")
    #expect(config.vodHost == "http://vod.yoitv.com:9083")
    #expect(config.recordHost == "http://record.yoitv.com:9083")
    #expect(config.liveUid == "LIVE_UID")
  }

  @Test("recordHost falls back through vmsVodHost then vmsHost")
  func recordHostFallbackChain() {
    let configWithVod = ProductConfig(
      vmsHost: "http://live.yoitv.com:9083",
      vmsVodHost: "http://vod.yoitv.com:9083",
      vmsUid: "UID", vmsLiveCid: "CID", vmsReferer: "ref",
      epgDays: nil, single: nil,
      vmsChannelListHost: nil, vmsLiveHost: nil, vmsRecordHost: nil, vmsLiveUid: nil
    )
    #expect(configWithVod.recordHost == "http://vod.yoitv.com:9083")
  }
}

// MARK: - ChannelListResponse Tests

@Suite("ChannelListResponse")
struct ChannelListResponseTests {
  static let channelJSON = """
    {
      "result": [
        {
          "id": "AA6EC2B2BC19EFE5FA44BE23187CDA63",
          "uid": "C2D9261F3D5753E74E97EB28FE2D8B26",
          "name": "NHK総合・東京",
          "description": "[HD]NHK General",
          "tags": "$LIVE_CAT_関東",
          "no": 101024,
          "timeshift": 1,
          "timeshift_len": 900,
          "epg_keep_days": 28,
          "state": 2,
          "running": 1,
          "playpath": "/query/s/Hqm-m7jqkFlA1CloJoaJZQ==",
          "live_type": "video"
        },
        {
          "id": "BB7FC3C3CD2A0FF6GB55CF34298EEB74",
          "name": "テレビ大阪",
          "tags": "$LIVE_CAT_関西, $LIVE_CAT_BS",
          "no": 201001,
          "playpath": "/query/s/TestPath=="
        }
      ],
      "code": "OK"
    }
    """

  @Test("Decodes channel list response")
  func decodesChannelList() throws {
    let data = Self.channelJSON.data(using: .utf8)!
    let response = try JSONDecoder().decode(ChannelListResponse.self, from: data)

    #expect(response.code == "OK")
    #expect(response.result.count == 2)

    let nhk = response.result[0]
    #expect(nhk.id == "AA6EC2B2BC19EFE5FA44BE23187CDA63")
    #expect(nhk.name == "NHK総合・東京")
    #expect(nhk.description == "[HD]NHK General")
    #expect(nhk.playpath == "/query/s/Hqm-m7jqkFlA1CloJoaJZQ==")
    #expect(nhk.no == 101024)
    #expect(nhk.running == 1)
    #expect(nhk.timeshift == 1)
    #expect(nhk.timeshiftLen == 900)
    #expect(nhk.epgKeepDays == 28)
    #expect(nhk.liveType == "video")
  }

  @Test("Parses single category from tags")
  func parseSingleCategory() throws {
    let data = Self.channelJSON.data(using: .utf8)!
    let response = try JSONDecoder().decode(ChannelListResponse.self, from: data)
    let nhk = response.result[0]

    #expect(nhk.categories == ["関東"])
    #expect(nhk.primaryCategory == "関東")
  }

  @Test("Parses multiple categories from comma-separated tags")
  func parseMultipleCategories() throws {
    let data = Self.channelJSON.data(using: .utf8)!
    let response = try JSONDecoder().decode(ChannelListResponse.self, from: data)
    let osaka = response.result[1]

    #expect(osaka.categories == ["関西", "BS"])
    #expect(osaka.primaryCategory == "関西")
  }

  @Test("Returns 'Others' when no LIVE_CAT tags")
  func noCategoryDefaultsToOthers() {
    let dto = ChannelDTO(
      id: "X", uid: nil, name: "Test", description: nil,
      tags: "some_other_tag", no: 1, timeshift: nil, timeshiftLen: nil,
      epgKeepDays: nil, state: nil, running: nil, playpath: "/test", liveType: nil
    )
    #expect(dto.primaryCategory == "Others")
    #expect(dto.categories.isEmpty)
  }

  @Test("Handles nil tags gracefully")
  func nilTags() {
    let dto = ChannelDTO(
      id: "X", uid: nil, name: "Test", description: nil,
      tags: nil, no: 1, timeshift: nil, timeshiftLen: nil,
      epgKeepDays: nil, state: nil, running: nil, playpath: "/test", liveType: nil
    )
    #expect(dto.primaryCategory == "Others")
    #expect(dto.categories.isEmpty)
  }

  @Test("Handles optional fields being absent in JSON")
  func handlesOptionalFields() throws {
    let minimalJSON = """
      {
        "result": [{"id": "X", "name": "Minimal", "no": 1, "playpath": "/test"}],
        "code": "OK"
      }
      """
    let data = minimalJSON.data(using: .utf8)!
    let response = try JSONDecoder().decode(ChannelListResponse.self, from: data)
    let ch = response.result[0]

    #expect(ch.uid == nil)
    #expect(ch.description == nil)
    #expect(ch.tags == nil)
    #expect(ch.running == nil)
    #expect(ch.timeshift == nil)
    #expect(ch.liveType == nil)
  }
}

// MARK: - EPGResponse Tests

@Suite("EPGResponse")
struct EPGResponseTests {
  static let epgJSON = """
    {
      "result": [{
        "id": "AA6EC2B2BC19EFE5FA44BE23187CDA63",
        "name": "NHK総合・東京",
        "record_epg": "[{\\"time\\":1768338000,\\"title\\":\\"NHKニュース おはよう日本\\",\\"path\\":\\"/query/wtkmHz1XU-dOl-so_i2LJlsegL7gV3_laXirRbM5SSM=\\"},{\\"time\\":1768341600,\\"title\\":\\"連続テレビ小説\\",\\"path\\":\\"\\"}]"
      }],
      "code": "OK"
    }
    """

  @Test("Decodes EPG channel response")
  func decodesResponse() throws {
    let data = Self.epgJSON.data(using: .utf8)!
    let response = try JSONDecoder().decode(EPGChannelResponse.self, from: data)

    #expect(response.code == "OK")
    #expect(response.result.count == 1)
    #expect(response.result[0].id == "AA6EC2B2BC19EFE5FA44BE23187CDA63")
  }

  @Test("Parses double-encoded EPG entries")
  func parsesEPGEntries() throws {
    let data = Self.epgJSON.data(using: .utf8)!
    let response = try JSONDecoder().decode(EPGChannelResponse.self, from: data)
    let entries = try response.result[0].parseEPGEntries()

    #expect(entries.count == 2)

    #expect(entries[0].time == 1768338000)
    #expect(entries[0].title == "NHKニュース おはよう日本")
    #expect(entries[0].path == "/query/wtkmHz1XU-dOl-so_i2LJlsegL7gV3_laXirRbM5SSM=")
    #expect(entries[0].hasVOD == true)

    #expect(entries[1].time == 1768341600)
    #expect(entries[1].title == "連続テレビ小説")
    #expect(entries[1].path == "")
    #expect(entries[1].hasVOD == false)
  }

  @Test("Returns empty array when record_epg is nil")
  func nilRecordEpg() throws {
    let dto = EPGChannelDTO(id: "X", name: "Test", recordEpg: nil)
    let entries = try dto.parseEPGEntries()
    #expect(entries.isEmpty)
  }

  @Test("Returns empty array when record_epg is empty string")
  func emptyRecordEpg() throws {
    let dto = EPGChannelDTO(id: "X", name: "Test", recordEpg: "")
    let entries = try dto.parseEPGEntries()
    #expect(entries.isEmpty)
  }
}

// MARK: - PlayRecordResponse Tests

@Suite("PlayRecordResponse")
struct PlayRecordResponseTests {
  static let responseJSON = """
    {
      "code": "OK",
      "data": [
        {
          "vid": "1813E2FB2946FB4176867F5AFB944899",
          "name": "ＤａｙＤａｙ．",
          "duration": 6271899,
          "pos": 701697,
          "platAt": 1770727745,
          "channelId": "CAD5FED3093396B3A4D49F326DE10CBD",
          "channelName": "日テレ",
          "playAt": 1770727043
        }
      ]
    }
    """

  @Test("Decodes play record list response")
  func decodesResponse() throws {
    let data = Self.responseJSON.data(using: .utf8)!
    let response = try JSONDecoder().decode(PlayRecordListResponse.self, from: data)

    #expect(response.code == "OK")
    #expect(response.data?.count == 1)

    let record = response.data![0]
    #expect(record.vid == "1813E2FB2946FB4176867F5AFB944899")
    #expect(record.name == "ＤａｙＤａｙ．")
    #expect(record.duration == 6271899)
    #expect(record.pos == 701697)
    #expect(record.channelId == "CAD5FED3093396B3A4D49F326DE10CBD")
    #expect(record.channelName == "日テレ")
    #expect(record.playAt == 1770727043)
    #expect(record.platAt == 1770727745)
  }

  @Test("Calculates progress correctly")
  func progressCalculation() {
    let record = PlayRecordDTO(
      vid: "X", name: "Test", duration: 1000, pos: 500,
      playAt: nil, platAt: nil, channelId: nil, channelName: nil
    )
    #expect(record.progress == 0.5)
  }

  @Test("Progress is zero when duration is zero")
  func zeroDurationProgress() {
    let record = PlayRecordDTO(
      vid: "X", name: "Test", duration: 0, pos: 100,
      playAt: nil, platAt: nil, channelId: nil, channelName: nil
    )
    #expect(record.progress == 0.0)
  }

  @Test("Progress is capped at 1.0")
  func cappedProgress() {
    let record = PlayRecordDTO(
      vid: "X", name: "Test", duration: 100, pos: 200,
      playAt: nil, platAt: nil, channelId: nil, channelName: nil
    )
    #expect(record.progress == 1.0)
  }
}

// MARK: - Favorites & SinglePlay Tests

@Suite("FavoritesResponse")
struct FavoritesResponseTests {
  @Test("Decodes live favorites list")
  func decodesLiveFavorites() throws {
    let json = """
      {"data": [{"vid": "CH1", "name": "NHK", "childLock": 0, "sortOrder": 1}], "max": 300, "code": "OK"}
      """
    let response = try JSONDecoder().decode(FavoriteLiveListResponse.self, from: json.data(using: .utf8)!)
    #expect(response.code == "OK")
    #expect(response.data?.count == 1)
    #expect(response.data?[0].vid == "CH1")
    #expect(response.max == 300)
  }

  @Test("Decodes VOD favorites list")
  func decodesVodFavorites() throws {
    let json = """
      {"records": [{"vid": "V1", "name": "Show", "channelId": "C1", "channelName": "NHK", "childLock": 0, "dupVid": "DV1"}], "lastKey": null, "max": 1000, "code": "OK"}
      """
    let response = try JSONDecoder().decode(FavoriteVodListResponse.self, from: json.data(using: .utf8)!)
    #expect(response.code == "OK")
    #expect(response.records?.count == 1)
    #expect(response.records?[0].dupVid == "DV1")
  }
}

@Suite("SinglePlayResponse")
struct SinglePlayResponseTests {
  @Test("Decodes single play response - owning")
  func decodesOwning() throws {
    let json = #"{"own": true, "code": "OK"}"#
    let response = try JSONDecoder().decode(SinglePlayResponse.self, from: json.data(using: .utf8)!)
    #expect(response.own == true)
  }

  @Test("Decodes single play response - not owning")
  func decodesNotOwning() throws {
    let json = #"{"own": false, "code": "OK"}"#
    let response = try JSONDecoder().decode(SinglePlayResponse.self, from: json.data(using: .utf8)!)
    #expect(response.own == false)
  }
}

// MARK: - SwiftData Channel Model Tests

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

// MARK: - EPGEntry Model Tests

@Suite("EPGEntry model")
struct EPGEntryModelTests {
  @Test("Initializes from EPGEntryDTO")
  func initFromDTO() {
    let dto = EPGEntryDTO(
      time: 1768338000,
      title: "NHKニュース おはよう日本",
      path: "/query/wtkmHz1XU-dOl-so_i2LJlsegL7gV3_laXirRbM5SSM="
    )
    let entry = EPGEntry(from: dto, channelID: "CH1")

    #expect(entry.channelID == "CH1")
    #expect(entry.title == "NHKニュース おはよう日本")
    #expect(entry.path == "/query/wtkmHz1XU-dOl-so_i2LJlsegL7gV3_laXirRbM5SSM=")
    #expect(entry.hasVOD == true)
    #expect(entry.startTime == Date(timeIntervalSince1970: 1768338000))
  }

  @Test("hasVOD is false when path is empty")
  func noVOD() {
    let entry = EPGEntry()
    entry.path = ""
    #expect(entry.hasVOD == false)

    entry.path = "/query/something"
    #expect(entry.hasVOD == true)
  }

  @Test("Formats time in JST")
  func jstFormatting() {
    // 2025-01-13 06:00:00 UTC = 2025-01-13 15:00:00 JST
    let dto = EPGEntryDTO(time: 1736748000, title: "Test", path: "")
    let entry = EPGEntry(from: dto, channelID: "CH1")
    #expect(entry.formattedTime == "15:00")
  }
}

// MARK: - PlayRecord Model Tests

@Suite("PlayRecord model")
struct PlayRecordModelTests {
  @Test("Initializes from PlayRecordDTO")
  func initFromDTO() {
    let dto = PlayRecordDTO(
      vid: "V1", name: "ＤａｙＤａｙ．",
      duration: 6271899, pos: 701697,
      playAt: 1770727043, platAt: 1770727745,
      channelId: "C1", channelName: "日テレ"
    )
    let record = PlayRecord(from: dto)

    #expect(record.vid == "V1")
    #expect(record.name == "ＤａｙＤａｙ．")
    #expect(record.durationMs == 6271899)
    #expect(record.positionMs == 701697)
    #expect(record.channelID == "C1")
    #expect(record.channelName == "日テレ")
    #expect(record.playedAt == Date(timeIntervalSince1970: 1770727043))
  }

  @Test("Falls back to platAt when playAt is nil")
  func platAtFallback() {
    let dto = PlayRecordDTO(
      vid: "V1", name: "Test", duration: 1000, pos: 500,
      playAt: nil, platAt: 1770727745, channelId: nil, channelName: nil
    )
    let record = PlayRecord(from: dto)
    #expect(record.playedAt == Date(timeIntervalSince1970: 1770727745))
  }

  @Test("Progress calculation")
  func progress() {
    let record = PlayRecord()
    record.durationMs = 1000
    record.positionMs = 500
    #expect(record.progress == 0.5)

    record.durationMs = 0
    #expect(record.progress == 0.0)

    record.durationMs = 100
    record.positionMs = 200
    #expect(record.progress == 1.0)
  }

  @Test("Duration formatting")
  func formatting() {
    #expect(PlayRecord.formatMilliseconds(0) == "0:00")
    #expect(PlayRecord.formatMilliseconds(61000) == "1:01")
    #expect(PlayRecord.formatMilliseconds(3661000) == "1:01:01")
    #expect(PlayRecord.formatMilliseconds(6271899) == "1:44:31")
  }
}

// MARK: - KeychainService Tests

@Suite("KeychainService")
struct KeychainServiceTests {
  @Test("Device ID is 32 hex characters")
  func deviceIDFormat() {
    let id = KeychainService.generateDeviceID()
    #expect(id.count == 32)
    #expect(id.allSatisfy { $0.isHexDigit })
  }

  @Test("Device ID generation produces unique values")
  func deviceIDUniqueness() {
    let ids = (0..<100).map { _ in KeychainService.generateDeviceID() }
    let unique = Set(ids)
    #expect(unique.count == 100)
  }

  @Test("MockKeychainService stores and retrieves session")
  func mockStoresSession() async throws {
    let mock = MockKeychainService()

    try await mock.storeSession(
      accessToken: "token123",
      refreshToken: "refresh456",
      cid: "CID789",
      productConfigJSON: "{}"
    )

    #expect(try await mock.accessToken() == "token123")
    #expect(try await mock.refreshToken() == "refresh456")
    #expect(try await mock.cid() == "CID789")
    #expect(try await mock.productConfigJSON() == "{}")
  }

  @Test("MockKeychainService clearSession removes credentials")
  func mockClearsSession() async throws {
    let mock = MockKeychainService()

    try await mock.storeSession(
      accessToken: "token", refreshToken: "refresh",
      cid: "cid", productConfigJSON: "{}"
    )
    try await mock.clearSession()

    #expect(try await mock.accessToken() == nil)
    #expect(try await mock.refreshToken() == nil)
    #expect(try await mock.cid() == nil)
    #expect(try await mock.productConfigJSON() == nil)
  }

  @Test("MockKeychainService generates and persists device ID")
  func mockDeviceID() async throws {
    let mock = MockKeychainService()
    let id1 = try await mock.deviceID()
    let id2 = try await mock.deviceID()
    #expect(id1 == id2)
    #expect(id1.count == 32)
  }

  @Test("MockKeychainService allows setting deterministic device ID")
  func mockSetDeviceID() async throws {
    let mock = MockKeychainService()
    await mock.setDeviceID("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1")
    let id = try await mock.deviceID()
    #expect(id == "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1")
  }

  @Test("clearSession does not remove device ID")
  func clearPreservesDeviceID() async throws {
    let mock = MockKeychainService()
    let id = try await mock.deviceID()

    try await mock.storeSession(
      accessToken: "t", refreshToken: "r", cid: "c", productConfigJSON: "{}"
    )
    try await mock.clearSession()

    let idAfterClear = try await mock.deviceID()
    #expect(id == idAfterClear)
  }
}

// MARK: - Networking Tests (serialized — shared MockURLProtocol state)

@Suite("Networking", .serialized)
struct NetworkingTests {

@Suite("MockURLProtocol")
struct MockURLProtocolTests {
  @Test("Intercepts requests and returns mock response")
  func interceptsRequests() async throws {
    MockURLProtocol.reset()
    MockURLProtocol.requestHandler = { request in
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200,
        httpVersion: "HTTP/1.1", headerFields: nil
      )!
      return (response, Data("hello".utf8))
    }

    let session = URLSession.mock()
    let (data, response) = try await session.data(from: URL(string: "https://example.com/test")!)
    let httpResponse = response as! HTTPURLResponse

    #expect(httpResponse.statusCode == 200)
    #expect(String(data: data, encoding: .utf8) == "hello")
    #expect(MockURLProtocol.capturedRequests.count == 1)
    #expect(MockURLProtocol.capturedRequests[0].url?.absoluteString == "https://example.com/test")
  }

  @Test("MockRouter matches routes by path")
  func routerMatching() async throws {
    MockURLProtocol.reset()
    var router = MockRouter()
    router.on(pathContaining: "logon.sjs", jsonFixture: #"{"code":"OK"}"#)
    router.on(pathContaining: "listLives", jsonFixture: #"{"result":[],"code":"OK"}"#)
    MockURLProtocol.requestHandler = router.handler()

    let session = URLSession.mock()

    let (data1, _) = try await session.data(from: URL(string: "https://crm.yoitv.com/logon.sjs?cid=test")!)
    #expect(String(data: data1, encoding: .utf8)!.contains("OK"))

    let (data2, _) = try await session.data(from: URL(string: "http://live.yoitv.com:9083/api?action=listLives")!)
    #expect(String(data: data2, encoding: .utf8)!.contains("result"))
  }

  @Test("MockRouter throws on unmatched request")
  func routerUnmatched() async {
    MockURLProtocol.reset()
    let router = MockRouter()
    MockURLProtocol.requestHandler = router.handler()

    let session = URLSession.mock()
    do {
      _ = try await session.data(from: URL(string: "https://unknown.com")!)
      #expect(Bool(false), "Should have thrown")
    } catch {
      // Verify we got an error (URLSession may or may not wrap the protocol error)
      let nsError = error as NSError
      #expect(nsError.domain.contains("MockURLProtocolError"))
    }
  }
}

// MARK: - APIClient Tests

@Suite("YoiTVEndpoints")
struct YoiTVEndpointsTests {
  @Test("Login URL contains all required parameters")
  func loginURL() {
    let url = YoiTVEndpoints.loginURL(cid: "AABC538835997", password: "testpass", deviceID: "AABB1122")
    let str = url.absoluteString

    #expect(str.contains("crm.yoitv.com/logon.sjs"))
    #expect(str.contains("from_app=1"))
    #expect(str.contains("cid=AABC538835997"))
    #expect(str.contains("password=testpass"))
    #expect(str.contains("app_id="))
    #expect(str.contains("device_id=AABB1122"))
  }

  @Test("Refresh URL contains all required parameters")
  func refreshURL() {
    let url = YoiTVEndpoints.refreshURL(refreshToken: "refresh123", cid: "CID1", deviceID: "DEV1")
    let str = url.absoluteString

    #expect(str.contains("crm.yoitv.com/refresh.sjs"))
    #expect(str.contains("refresh_token=refresh123"))
    #expect(str.contains("cid=CID1"))
    #expect(str.contains("device_id=DEV1"))
  }

  @Test("Channel list URL uses config hosts")
  func channelListURL() {
    let config = ProductConfig(
      vmsHost: "http://live.yoitv.com:9083",
      vmsVodHost: nil, vmsUid: "UID1", vmsLiveCid: "CID1",
      vmsReferer: "http://play.yoitv.com", epgDays: 30, single: nil,
      vmsChannelListHost: nil, vmsLiveHost: nil, vmsRecordHost: nil, vmsLiveUid: nil
    )
    let url = YoiTVEndpoints.channelListURL(config: config)
    let str = url.absoluteString

    #expect(str.hasPrefix("http://live.yoitv.com:9083/api"))
    #expect(str.contains("action=listLives"))
    #expect(str.contains("cid=CID1"))
    #expect(str.contains("uid=UID1"))
    #expect(str.contains("no_epg=1"))
    #expect(str.contains("page_size=200"))
  }

  @Test("EPG URL includes channel ID and no_epg=0")
  func epgURL() {
    let config = ProductConfig(
      vmsHost: "http://live.yoitv.com:9083",
      vmsVodHost: nil, vmsUid: "UID1", vmsLiveCid: "CID1",
      vmsReferer: "http://play.yoitv.com", epgDays: 30, single: nil,
      vmsChannelListHost: nil, vmsLiveHost: nil, vmsRecordHost: nil, vmsLiveUid: nil
    )
    let url = YoiTVEndpoints.epgURL(config: config, channelID: "CHAN123")
    let str = url.absoluteString

    #expect(str.contains("vid=CHAN123"))
    #expect(str.contains("no_epg=0"))
    #expect(str.contains("epg_days=30"))
  }

  @Test("Single play URL formats correctly")
  func singlePlayURL() {
    let url = YoiTVEndpoints.singlePlayURL(
      singleEndpoint: "https://crm.yoitv.com/single.sjs",
      ua: "ios", own: true, accessToken: "token123"
    )
    let str = url.absoluteString

    #expect(str.contains("single.sjs"))
    #expect(str.contains("ua=ios"))
    #expect(str.contains("own=true"))
    #expect(str.contains("access_token=token123"))
  }

  @Test("Bearer headers format correctly")
  func bearerHeaders() {
    let headers = YoiTVEndpoints.bearerHeaders(accessToken: "mytoken")
    #expect(headers["Authorization"] == "Bearer mytoken")
  }

  @Test("CRM URL builds with controller and action")
  func crmURL() {
    let url = YoiTVEndpoints.crmURL(controller: "tvum_favorite", action: "listLive")
    let str = url.absoluteString
    #expect(str.contains("crm.yoitv.com/tvum"))
    #expect(str.contains("controller=tvum_favorite"))
    #expect(str.contains("action=listLive"))
  }
}

@Suite("APIClient")
struct APIClientTests {
  @Test("GET request decodes JSON response")
  func getRequest() async throws {
    MockURLProtocol.reset()
    MockURLProtocol.requestHandler = { _ in
      let json = #"{"code":"OK","result":[]}"#
      let response = HTTPURLResponse(
        url: URL(string: "https://example.com")!,
        statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(json.utf8))
    }

    let client = APIClient(session: .mock())
    let result: ChannelListResponse = try await client.get(url: URL(string: "https://example.com/api")!)
    #expect(result.code == "OK")
    #expect(result.result.isEmpty)
  }

  @Test("GET request throws on HTTP error")
  func getHTTPError() async {
    MockURLProtocol.reset()
    MockURLProtocol.requestHandler = { _ in
      let response = HTTPURLResponse(
        url: URL(string: "https://example.com")!,
        statusCode: 403, httpVersion: nil, headerFields: nil
      )!
      return (response, Data())
    }

    let client = APIClient(session: .mock())
    do {
      let _: ChannelListResponse = try await client.get(url: URL(string: "https://example.com")!)
      #expect(Bool(false), "Should have thrown")
    } catch let error as APIError {
      #expect(error == .httpError(statusCode: 403))
    } catch {
      #expect(Bool(false), "Wrong error type: \(error)")
    }
  }

  @Test("POST request sends JSON body and decodes response")
  func postRequest() async throws {
    MockURLProtocol.reset()
    MockURLProtocol.requestHandler = { request in
      // Verify Content-Type header
      #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
      // Verify Authorization header
      #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer mytoken")
      // Verify body is present
      #expect(request.httpBody != nil || request.httpBodyStream != nil)

      let json = #"{"code":"OK"}"#
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(json.utf8))
    }

    let client = APIClient(session: .mock())
    let body = FavoriteLiveSyncRequest(updates: nil, removals: ["CH1"])
    let result: FavoriteLiveListResponse = try await client.post(
      url: URL(string: "https://crm.yoitv.com/tvum")!,
      headers: YoiTVEndpoints.bearerHeaders(accessToken: "mytoken"),
      body: body
    )
    #expect(result.code == "OK")
  }
}

} // end NetworkingTests

// MARK: - StreamURLBuilder Tests

@Suite("StreamURLBuilder")
struct StreamURLBuilderTests {
  @Test("Live URL uses uppercase .M3U8")
  func liveURLFormat() {
    let url = StreamURLBuilder.liveStreamURL(
      liveHost: "http://live.yoitv.com:9083",
      playpath: "/query/s/Hqm-m7jqkFlA1CloJoaJZQ==",
      accessToken: "testtoken"
    )
    #expect(url != nil)
    let str = url!.absoluteString
    #expect(str.contains(".M3U8"))
    #expect(str.contains("type=live"))
    #expect(str.contains("__cross_domain_user="))
  }

  @Test("VOD URL uses lowercase .m3u8")
  func vodURLFormat() {
    let url = StreamURLBuilder.vodStreamURL(
      recordHost: "http://vod.yoitv.com:9083",
      path: "/query/wtkmHz1XU-dOl-so_i2LJlsegL7gV3_laXirRbM5SSM=",
      accessToken: "testtoken"
    )
    #expect(url != nil)
    let str = url!.absoluteString
    #expect(str.contains(".m3u8"))
    #expect(!str.contains(".M3U8"))
    #expect(str.contains("type=vod"))
  }

  @Test("Access token with +, /, = is percent-encoded")
  func tokenEncoding() {
    let token = "abc+def/ghi=jkl=="
    let encoded = StreamURLBuilder.percentEncodeToken(token)

    #expect(!encoded.contains("+"))
    #expect(!encoded.contains("/"))
    // = should be encoded
    #expect(encoded.contains("%2B"))  // +
    #expect(encoded.contains("%2F"))  // /
    #expect(encoded.contains("%3D"))  // =
  }

  @Test("Live URL correctly encodes base64 access token")
  func liveURLWithBase64Token() {
    let url = StreamURLBuilder.liveStreamURL(
      liveHost: "http://live.yoitv.com:9083",
      playpath: "/query/s/test",
      accessToken: "ZZVWXJbb+test/token=Krg=="
    )
    let str = url!.absoluteString
    // Token special chars should be percent-encoded
    #expect(!str.contains("+"))  // Should be %2B
    #expect(str.contains("%2B"))
    #expect(str.contains("%2F"))
    #expect(str.contains("%3D"))
  }

  @Test("Favorite VOD URL uses dupVid when available")
  func favoriteVodWithDupVid() {
    let url = StreamURLBuilder.favoriteVodStreamURL(
      vodHost: "http://vod.yoitv.com:9083",
      vid: "originalVid",
      dupVid: "duplicateVid",
      accessToken: "token"
    )
    let str = url!.absoluteString
    #expect(str.contains("/query/duplicateVid.m3u8"))
    #expect(!str.contains("originalVid"))
  }

  @Test("Favorite VOD URL uses vid when dupVid is nil")
  func favoriteVodWithoutDupVid() {
    let url = StreamURLBuilder.favoriteVodStreamURL(
      vodHost: "http://vod.yoitv.com:9083",
      vid: "originalVid",
      dupVid: nil,
      accessToken: "token"
    )
    let str = url!.absoluteString
    #expect(str.contains("/query/originalVid.m3u8"))
  }

  @Test("Thumbnail URL has no auth parameter")
  func thumbnailURL() {
    let url = StreamURLBuilder.thumbnailURL(
      channelListHost: "http://live.yoitv.com:9083",
      playpath: "/query/s/Hqm-m7jqkFlA1CloJoaJZQ=="
    )
    let str = url!.absoluteString
    #expect(str.contains(".jpg"))
    #expect(str.contains("thumbnail=thumbnail_small.jpg"))
    #expect(!str.contains("__cross_domain_user"))
  }

  @Test("Asset options contain Referer header")
  func assetOptions() {
    let options = StreamURLBuilder.assetOptions(referer: "http://play.yoitv.com")
    let headers = options["AVURLAssetHTTPHeaderFieldsKey"] as? [String: String]
    #expect(headers?["Referer"] == "http://play.yoitv.com")
  }

  @Test("Stream URLs use hosts from ProductConfig")
  func usesConfigHosts() {
    let config = ProductConfig(
      vmsHost: "http://live.yoitv.com:9083",
      vmsVodHost: "http://vod.yoitv.com:9083",
      vmsUid: "UID", vmsLiveCid: "CID",
      vmsReferer: "http://play.yoitv.com",
      epgDays: nil, single: nil,
      vmsChannelListHost: nil, vmsLiveHost: "http://live-custom:9083",
      vmsRecordHost: "http://record-custom:9083", vmsLiveUid: nil
    )

    let liveURL = StreamURLBuilder.liveStreamURL(
      liveHost: config.liveHost,
      playpath: "/query/s/test",
      accessToken: "t"
    )
    #expect(liveURL!.absoluteString.hasPrefix("http://live-custom:9083"))

    let vodURL = StreamURLBuilder.vodStreamURL(
      recordHost: config.recordHost,
      path: "/query/test",
      accessToken: "t"
    )
    #expect(vodURL!.absoluteString.hasPrefix("http://record-custom:9083"))
  }
}
