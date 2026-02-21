#if DEBUG
import Foundation
import SwiftUI

// MARK: - Fixture API Client

/// API client that serves captured fixture data for SwiftUI previews.
/// Routes requests based on URL query parameters:
/// - `no_epg=1` (no `vid=`) → channels.json (ChannelListResponse)
/// - `no_epg=0` with `vid=X` → EPG fixture (ChannelProgramsResponse)
actor FixtureAPIClient: APIClientProtocol {
  private static let epgFixtures: [String: String] = [
    "AA6EC2B2BC19EFE5FA44BE23187CDA63": "epg-nhk-g",
    "CAD5FED3093396B3A4D49F326DE10CBD": "epg-nittere",
  ]

  func get<T: Decodable & Sendable>(
    url: URL,
    headers: [String: String]
  ) async throws -> T {
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let queryItems = components?.queryItems ?? []

    let vid = queryItems.first { $0.name == "vid" }?.value

    let fixtureName: String
    if let vid {
      fixtureName = Self.epgFixtures[vid] ?? "epg-nhk-g"
    } else {
      fixtureName = "channels"
    }

    let data = try Self.loadFixture(named: fixtureName)
    return try JSONDecoder().decode(T.self, from: data)
  }

  func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(
    url: URL,
    headers: [String: String],
    body: Body
  ) async throws -> Response {
    fatalError("Unused in preview")
  }

  private static func loadFixture(named name: String) throws -> Data {
    guard let url = Bundle.module.url(
      forResource: name,
      withExtension: "json",
      subdirectory: "PreviewContent/fixtures"
    ) else {
      fatalError("Missing fixture: PreviewContent/fixtures/\(name).json")
    }
    return try Data(contentsOf: url)
  }
}

// MARK: - Preview Container

/// Uses the real VMS host so channel thumbnails load (they don't require auth).
private let fixtureProductConfig: ProductConfig = {
  try! JSONDecoder().decode(ProductConfig.self, from: Data("""
  {"vms_host":"http://live.yoitv.com:9083","vms_uid":"uid","vms_live_cid":"cid","vms_referer":"http://play.yoitv.com"}
  """.utf8))
}()

private let fixtureSession = AuthService.Session(
  accessToken: "tok", refreshToken: "ref", cid: "cid", config: fixtureProductConfig
)

/// Self-contained preview of the authenticated app using fixture data.
struct FixtureContainerPreview: View {
  @State private var appState: AppState

  init() {
    let fixture: any APIClientProtocol = FixtureAPIClient()
    let keychain = KeychainService()
    _appState = State(initialValue: AppState(
      keychain: keychain,
      apiClient: APIClient(),
      authService: AuthService(keychain: keychain, apiClient: fixture),
      channelService: ChannelService(apiClient: fixture, config: fixtureProductConfig),
      programGuideService: ProgramGuideService(apiClient: fixture, config: fixtureProductConfig)
    ))
  }

  var body: some View {
    AuthenticatedContainer(appState: appState, session: fixtureSession)
  }
}
#endif
