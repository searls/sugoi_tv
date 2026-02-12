import SwiftUI

/// Glues a channel selection to PlayerManager for live stream playback
struct ChannelPlayerView: View {
  let channel: ChannelDTO
  let session: AuthService.Session
  @State private var playerManager = PlayerManager()

  var body: some View {
    PlayerView(playerManager: playerManager)
      .navigationTitle(channel.name)
      #if !os(macOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .onAppear { startPlayback() }
      .onDisappear { playerManager.stop() }
  }

  private func startPlayback() {
    guard let url = StreamURLBuilder.liveStreamURL(
      liveHost: session.productConfig.liveHost,
      playpath: channel.playpath,
      accessToken: session.accessToken
    ) else { return }

    let referer = session.productConfig.vmsReferer
    playerManager.loadLiveStream(url: url, referer: referer)
  }
}
