import AVFoundation
import AVKit
import SwiftUI

/// Cross-platform video player.
/// macOS and iOS use AVPlayerLayer + custom SwiftUI controls with Liquid Glass styling.
/// tvOS uses SwiftUI's VideoPlayer with system controls.
public struct PlayerView: View {
  let playerManager: PlayerManager
  var loadingTitle: String = ""
  var loadingThumbnailURL: URL?

  public init(playerManager: PlayerManager, loadingTitle: String = "", loadingThumbnailURL: URL? = nil) {
    self.playerManager = playerManager
    self.loadingTitle = loadingTitle
    self.loadingThumbnailURL = loadingThumbnailURL
  }

  public var body: some View {
    ZStack {
      Group {
        if let player = playerManager.player {
          platformPlayer(player: player)
            .ignoresSafeArea()
        } else {
          Color.black
            .ignoresSafeArea()
        }
      }

      if playerManager.state == .loading {
        StreamLoadingOverlay(title: loadingTitle, thumbnailURL: loadingThumbnailURL)
          .transition(.opacity)
      }
    }
    .animation(.easeInOut(duration: 0.3), value: playerManager.state == .loading)
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

// MARK: - Loading overlay

struct StreamLoadingOverlay: View {
  let title: String
  let thumbnailURL: URL?

  var body: some View {
    VStack(spacing: 12) {
      if let thumbnailURL {
        AsyncImage(url: thumbnailURL) { image in
          image
            .resizable()
            .aspectRatio(contentMode: .fit)
        } placeholder: {
          Color.clear
        }
        .frame(width: 80, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 12))
      }

      if !title.isEmpty {
        Text(title)
          .font(.title2.weight(.medium))
          .foregroundStyle(.white)
          .multilineTextAlignment(.center)
      }

      Text("Now loading")
        .font(.body)
        .foregroundStyle(.white.secondary)
    }
    .padding(.horizontal, 32)
    .padding(.vertical, 24)
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

