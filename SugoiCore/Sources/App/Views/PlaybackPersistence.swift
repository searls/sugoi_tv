import SwiftUI

/// Groups all @AppStorage properties related to playback state persistence.
/// Provides semantic methods for recording live/VOD playback and saving position.
struct PlaybackPersistence {
  @AppStorage("lastChannelId") var lastChannelId: String = ""
  @AppStorage("lastPlayingProgramID") var lastPlayingProgramID: String = ""
  @AppStorage("lastPlayingProgramTitle") var lastPlayingProgramTitle: String = ""
  @AppStorage("lastPlayingChannelName") var lastPlayingChannelName: String = ""
  @AppStorage("lastVODPosition") var lastVODPosition: Double = 0

  /// Record that a live channel is now playing. Clears any VOD-related persistence.
  mutating func recordLivePlay(channelId: String) {
    lastChannelId = channelId
    lastPlayingProgramID = ""
    lastPlayingProgramTitle = ""
    lastPlayingChannelName = ""
    lastVODPosition = 0
  }

  /// Record that a VOD program is now playing.
  mutating func recordVODPlay(programPath: String, title: String, channelName: String) {
    lastPlayingProgramID = programPath
    lastPlayingProgramTitle = title
    lastPlayingChannelName = channelName
  }

  /// Save the current playback position for VOD resume.
  mutating func savePosition(_ position: TimeInterval) {
    lastVODPosition = position
  }
}
