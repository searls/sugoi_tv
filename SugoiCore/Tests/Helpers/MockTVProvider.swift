import Foundation
import Synchronization

@testable import SugoiCore

/// In-memory TVProvider for tests. Returns fixture data and records calls.
final class MockTVProvider: TVProvider, @unchecked Sendable {
  let displayName: String
  let providerID: String
  let requiresAuthentication: Bool
  let displayTimezone: TimeZone

  private let state = Mutex(State())

  private struct State {
    var isAuthenticated: Bool = false
    var channels: [ChannelDTO] = []
    var programs: [String: [ProgramDTO]] = [:]
  }

  var isAuthenticated: Bool {
    state.withLock { $0.isAuthenticated }
  }

  var loginFields: [LoginField] {
    [
      LoginField(key: "cid", label: "Customer ID", contentType: .username),
      LoginField(key: "password", label: "Password", isSecure: true, contentType: .password),
    ]
  }

  private var _liveStreamRequest: ((ChannelDTO) -> StreamRequest?)?
  private var _vodStreamRequest: ((ProgramDTO) -> StreamRequest?)?

  init(
    displayName: String = "Mock",
    providerID: String = "mock",
    requiresAuthentication: Bool = true,
    displayTimezone: TimeZone = TimeZone(identifier: "Asia/Tokyo")!,
    isAuthenticated: Bool = false,
    channels: [ChannelDTO] = [],
    programs: [String: [ProgramDTO]] = [:]
  ) {
    self.displayName = displayName
    self.providerID = providerID
    self.requiresAuthentication = requiresAuthentication
    self.displayTimezone = displayTimezone
    state.withLock {
      $0.isAuthenticated = isAuthenticated
      $0.channels = channels
      $0.programs = programs
    }
  }

  // MARK: - Auth

  func login(credentials: [String: String]) async throws {
    state.withLock { $0.isAuthenticated = true }
  }

  func restoreSession() async throws -> Bool {
    state.withLock { $0.isAuthenticated }
  }

  func logout() async {
    state.withLock { $0.isAuthenticated = false }
  }

  func reauthenticate() async throws -> Bool {
    state.withLock { $0.isAuthenticated }
  }

  // MARK: - Channels

  func fetchChannels() async throws -> [ChannelDTO] {
    state.withLock { $0.channels }
  }

  func groupByCategory(_ channels: [ChannelDTO]) -> [(category: String, channels: [ChannelDTO])] {
    ChannelService.groupByCategory(channels)
  }

  func thumbnailURL(for channel: ChannelDTO) -> URL? { nil }

  // MARK: - Programs

  func fetchPrograms(channelID: String) async throws -> [ProgramDTO] {
    state.withLock { $0.programs[channelID] ?? [] }
  }

  // MARK: - Streaming

  func liveStreamRequest(for channel: ChannelDTO) -> StreamRequest? {
    _liveStreamRequest?(channel)
  }

  func vodStreamRequest(for program: ProgramDTO) -> StreamRequest? {
    _vodStreamRequest?(program)
  }

  // MARK: - Test helpers

  func setChannels(_ channels: [ChannelDTO]) {
    state.withLock { $0.channels = channels }
  }

  func setPrograms(_ programs: [ProgramDTO], for channelID: String) {
    state.withLock { $0.programs[channelID] = programs }
  }

  func setLiveStreamHandler(_ handler: @escaping (ChannelDTO) -> StreamRequest?) {
    _liveStreamRequest = handler
  }

  func setVODStreamHandler(_ handler: @escaping (ProgramDTO) -> StreamRequest?) {
    _vodStreamRequest = handler
  }
}
