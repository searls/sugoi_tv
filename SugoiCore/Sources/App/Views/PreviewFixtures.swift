#if DEBUG
import Foundation
import SwiftUI

// MARK: - Preview-only response types

/// Lightweight decodable wrapper for channels.json fixture.
private struct _ChannelListResponse: Decodable { let result: [ChannelDTO] }

/// Lightweight decodable wrapper for EPG fixtures.
private struct _ChannelProgramsResponse: Decodable { let result: [_ChannelProgramsDTO] }
private struct _ChannelProgramsDTO: Decodable {
  let id: String
  let name: String
  let programHistory: String?
  enum CodingKeys: String, CodingKey { case id, name, programHistory = "record_epg" }
  func parsePrograms() throws -> [ProgramDTO] {
    guard let json = programHistory, !json.isEmpty,
          let data = json.data(using: .utf8) else { return [] }
    return try JSONDecoder().decode([ProgramDTO].self, from: data)
  }
}

// MARK: - Fixture API Client

/// API client that serves captured fixture data for SwiftUI previews.
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

/// Uses fixture API client for channels/programs; no auth, no streaming.
private final class FixtureTVProvider: TVProvider, @unchecked Sendable {
  let displayName = "Preview"
  let providerID = "fixture"
  let requiresAuthentication = false
  let displayTimezone = TimeZone(identifier: "Asia/Tokyo")!

  private let fixtureClient = FixtureAPIClient()
  private let channelListHost = "http://live.yoitv.com:9083"

  var isAuthenticated: Bool { true }
  var loginFields: [LoginField] { [] }
  func login(credentials: [String: String]) async throws {}
  func restoreSession() async throws -> Bool { true }
  func logout() async {}
  func reauthenticate() async throws -> Bool { true }

  func fetchChannels() async throws -> [ChannelDTO] {
    let response: _ChannelListResponse = try await fixtureClient.get(
      url: URL(string: "\(channelListHost)/api?action=listLives&no_epg=1")!
    )
    return response.result
  }

  func groupByCategory(_ channels: [ChannelDTO]) -> [(category: String, channels: [ChannelDTO])] {
    channels.groupedByCategory()
  }

  func thumbnailURL(for channel: ChannelDTO) -> URL? {
    URL(string: "\(channelListHost)\(channel.playpath).jpg?type=live&thumbnail=thumbnail_small.jpg")
  }

  func fetchPrograms(channelID: String) async throws -> [ProgramDTO] {
    let response: _ChannelProgramsResponse = try await fixtureClient.get(
      url: URL(string: "\(channelListHost)/api?action=listLives&vid=\(channelID)&no_epg=0")!
    )
    guard let channelData = response.result.first else { return [] }
    return try channelData.parsePrograms()
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
