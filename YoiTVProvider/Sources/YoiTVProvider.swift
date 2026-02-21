import Foundation
import SugoiCore

/// Temporary adapter wrapping existing YoiTV services behind TVProvider.
/// Will be replaced by a standalone YoiTVProvider package in Phase 3.
public final class YoiTVProviderAdapter: TVProvider, @unchecked Sendable {
  public let displayName = "YoiTV"
  public let providerID = "yoitv"
  public let requiresAuthentication = true
  public let displayTimezone = TimeZone(identifier: "Asia/Tokyo")!

  private let keychain: any KeychainServiceProtocol
  private let apiClient: any APIClientProtocol
  private let authService: AuthService
  private var channelService: ChannelService?
  private var programGuideService: ProgramGuideService?

  /// Current session, updated on login/refresh/restore.
  private var session: AuthService.Session?

  public var isAuthenticated: Bool { session != nil }

  public var loginFields: [LoginField] {
    [
      LoginField(key: "cid", label: "Customer ID", contentType: .username),
      LoginField(key: "password", label: "Password", isSecure: true, contentType: .password),
    ]
  }

  public init(keychain: any KeychainServiceProtocol, apiClient: any APIClientProtocol) {
    self.keychain = keychain
    self.apiClient = apiClient
    self.authService = AuthService(keychain: keychain, apiClient: apiClient)
  }

  // MARK: - Auth

  public func login(credentials: [String: String]) async throws {
    guard let cid = credentials["cid"], let password = credentials["password"] else {
      throw AuthError.loginFailed(code: "missing_credentials")
    }
    let newSession = try await authService.login(cid: cid, password: password)
    session = newSession
    rebuildServices(config: newSession.productConfig)
  }

  public func restoreSession() async throws -> Bool {
    guard let restored = try await authService.restoreSession() else { return false }
    session = restored
    rebuildServices(config: restored.productConfig)

    // Background refresh
    do {
      let refreshed = try await authService.refreshTokens()
      session = refreshed
      rebuildServices(config: refreshed.productConfig)
    } catch AuthError.sessionExpired {
      session = nil
      return false
    } catch {
      // Network error — keep stale session
    }
    return true
  }

  public func logout() async {
    await authService.logout()
    session = nil
  }

  public func startAutoRefresh() async {
    await authService.startAutoRefresh()
  }

  public func reauthenticate() async throws -> Bool {
    do {
      let newSession = try await authService.reauthenticateWithStoredCredentials()
      session = newSession
      rebuildServices(config: newSession.productConfig)
      await authService.startAutoRefresh()
      return true
    } catch is AuthError {
      await logout()
      return false
    }
  }

  // MARK: - Channels

  public func fetchChannels() async throws -> [ChannelDTO] {
    guard let service = channelService else {
      throw ChannelServiceError.fetchFailed(code: "no_session")
    }
    return try await service.fetchChannels()
  }

  public func groupByCategory(_ channels: [ChannelDTO]) -> [(category: String, channels: [ChannelDTO])] {
    channels.groupedByCategory()
  }

  public func thumbnailURL(for channel: ChannelDTO) -> URL? {
    channelService?.thumbnailURL(for: channel)
  }

  // MARK: - Programs

  public func fetchPrograms(channelID: String) async throws -> [ProgramDTO] {
    guard let service = programGuideService else {
      throw ProgramGuideError.fetchFailed(code: "no_session")
    }
    return try await service.fetchPrograms(channelID: channelID)
  }

  // MARK: - Streaming

  public func liveStreamRequest(for channel: ChannelDTO) -> StreamRequest? {
    guard let session else { return nil }
    guard let url = StreamURLBuilder.liveStreamURL(
      liveHost: session.productConfig.liveHost,
      playpath: channel.playpath,
      accessToken: session.accessToken
    ) else { return nil }
    return StreamRequest(
      url: url,
      headers: ["Referer": session.productConfig.vmsReferer],
      requiresProxy: true
    )
  }

  public func vodStreamRequest(for program: ProgramDTO) -> StreamRequest? {
    guard program.hasVOD, let session else { return nil }
    guard let url = StreamURLBuilder.vodStreamURL(
      recordHost: session.productConfig.recordHost,
      path: program.path,
      accessToken: session.accessToken
    ) else { return nil }
    return StreamRequest(
      url: url,
      headers: ["Referer": session.productConfig.vmsReferer],
      requiresProxy: true
    )
  }

  // MARK: - Playback enforcement

  // SinglePlayService integration deferred — it was not wired through the controller before.

  // MARK: - Internal

  /// Access token for session observation.
  public var accessToken: String? { session?.accessToken }

  /// Account identifier (CID) for display in settings.
  public var accountID: String? { session?.cid }

  /// Referer for proxy initialization.
  public var vmsReferer: String? { session?.productConfig.vmsReferer }

  private func rebuildServices(config: ProductConfig) {
    channelService = ChannelService(apiClient: apiClient, config: config)
    programGuideService = ProgramGuideService(apiClient: apiClient, config: config)
  }
}
