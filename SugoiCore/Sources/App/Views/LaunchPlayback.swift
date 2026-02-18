import Foundation

/// Pure logic for deciding what to play on launch.
public enum LaunchPlayback {
  public enum Decision: Equatable {
    case doNothing
    case playLive
    case resumeVOD(programID: String, title: String, channelName: String, position: TimeInterval)
  }

  /// Decides what to auto-play when the app launches.
  /// - Parameters:
  ///   - isCompact: true on iPhone (compact horizontal size class)
  ///   - lastActiveTimestamp: seconds since 1970 of last activity (0 = first launch)
  ///   - now: current time in seconds since 1970
  ///   - lastProgramID: persisted VOD path, empty when last session was live
  ///   - lastProgramTitle: persisted VOD title
  ///   - lastChannelName: persisted channel name for the VOD
  ///   - lastVODPosition: persisted playback position in seconds
  ///   - staleThreshold: seconds of inactivity before session is considered stale (default 12h)
  public static func decide(
    isCompact: Bool,
    lastActiveTimestamp: TimeInterval,
    now: TimeInterval,
    lastProgramID: String,
    lastProgramTitle: String,
    lastChannelName: String,
    lastVODPosition: TimeInterval,
    staleThreshold: TimeInterval = 12 * 3600
  ) -> Decision {
    guard !isCompact else { return .doNothing }
    guard lastActiveTimestamp > 0 else { return .playLive } // first launch

    let elapsed = now - lastActiveTimestamp
    if elapsed >= staleThreshold { return .playLive }

    // Recent session with VOD in progress
    if !lastProgramID.isEmpty {
      return .resumeVOD(
        programID: lastProgramID,
        title: lastProgramTitle,
        channelName: lastChannelName,
        position: lastVODPosition
      )
    }

    return .playLive
  }
}
