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

// MARK: - Fixture TVProvider for previews

/// Uses fixture API client and real VMS host for thumbnails.
private final class FixtureTVProvider: TVProvider, @unchecked Sendable {
  let displayName = "YoiTV"
  let providerID = "fixture"
  let requiresAuthentication = true
  let displayTimezone = TimeZone(identifier: "Asia/Tokyo")!

  private let fixtureClient: any APIClientProtocol
  private let config: ProductConfig

  init() {
    self.fixtureClient = FixtureAPIClient()
    self.config = Self.fixtureConfig
  }

  private static let fixtureConfig: ProductConfig = {
    try! JSONDecoder().decode(ProductConfig.self, from: Data("""
    {"vms_host":"http://live.yoitv.com:9083","vms_uid":"uid","vms_live_cid":"cid","vms_referer":"http://play.yoitv.com"}
    """.utf8))
  }()

  var isAuthenticated: Bool { true }
  var loginFields: [LoginField] { [] }
  func login(credentials: [String: String]) async throws {}
  func restoreSession() async throws -> Bool { true }
  func logout() async {}
  func reauthenticate() async throws -> Bool { true }

  func fetchChannels() async throws -> [ChannelDTO] {
    let service = ChannelService(apiClient: fixtureClient, config: config)
    return try await service.fetchChannels()
  }

  func groupByCategory(_ channels: [ChannelDTO]) -> [(category: String, channels: [ChannelDTO])] {
    ChannelService.groupByCategory(channels)
  }

  func thumbnailURL(for channel: ChannelDTO) -> URL? {
    StreamURLBuilder.thumbnailURL(channelListHost: config.channelListHost, playpath: channel.playpath)
  }

  func fetchPrograms(channelID: String) async throws -> [ProgramDTO] {
    let service = ProgramGuideService(apiClient: fixtureClient, config: config)
    return try await service.fetchPrograms(channelID: channelID)
  }

  func liveStreamRequest(for channel: ChannelDTO) -> StreamRequest? { nil }
  func vodStreamRequest(for program: ProgramDTO) -> StreamRequest? { nil }
}

// MARK: - Preview Container

/// Self-contained preview of the authenticated app using fixture data.
struct FixtureContainerPreview: View {
  @State private var appState: AppState

  init() {
    let provider = FixtureTVProvider()
    let state = AppState(provider: provider)
    state.setAuthenticatedForPreview()
    _appState = State(initialValue: state)
  }

  var body: some View {
    AuthenticatedContainer(appState: appState)
  }
}
#endif
