import Foundation
import Testing

@testable import YoiTVProvider

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
