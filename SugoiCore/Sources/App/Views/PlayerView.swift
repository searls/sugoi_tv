import AVFoundation
import AVKit
import SwiftUI

/// Cross-platform video player.
/// macOS and iOS use AVPlayerLayer + custom SwiftUI controls with Liquid Glass styling.
/// tvOS uses SwiftUI's VideoPlayer with system controls.
public struct PlayerView: View {
  let playerManager: PlayerManager

  public init(playerManager: PlayerManager) {
    self.playerManager = playerManager
  }

  public var body: some View {
    Group {
      if let player = playerManager.player {
        platformPlayer(player: player)
          .ignoresSafeArea()
      } else {
        Color.black
          .ignoresSafeArea()
      }
    }
    .accessibilityIdentifier("playerView")
    .alert("Playback Error", isPresented: showingError) {
      Button("Retry") { playerManager.retry() }
      Button("Dismiss", role: .cancel) { playerManager.clearError() }
    } message: {
      Text(errorMessage)
    }
  }

  @ViewBuilder
  private func platformPlayer(player: AVPlayer) -> some View {
    #if os(tvOS)
    VideoPlayer(player: player)
    #else
    CustomPlayerView(playerManager: playerManager, player: player)
    #endif
  }

  private var showingError: Binding<Bool> {
    Binding(
      get: { if case .failed = playerManager.state { true } else { false } },
      set: { if !$0 { playerManager.clearError() } }
    )
  }

  private var errorMessage: String {
    if case .failed(let msg) = playerManager.state { return msg }
    return ""
  }
}

// MARK: - Preview

#if DEBUG
private struct PlayerViewPreview: View {
  @State private var manager = PlayerManager()

  var body: some View {
    PlayerView(playerManager: manager)
      .onAppear {
        if let url = Bundle.module.url(
          forResource: "test-video",
          withExtension: "mp4",
          subdirectory: "PreviewContent"
        ) {
          manager.loadVODStream(url: url, referer: "http://preview.local")
        }
      }
  }
}

#Preview("Player") {
  PlayerViewPreview()
}

private struct PlayerViewLivePreview: View {
  @State private var manager = PlayerManager()

  var body: some View {
    PlayerView(playerManager: manager)
      .onAppear {
        manager.loadLiveStream(
          url: URL(string: "http://example.com/test.M3U8")!,
          referer: "http://preview.local"
        )
      }
  }
}

#Preview("Player (Live)") {
  PlayerViewLivePreview()
}

#endif

