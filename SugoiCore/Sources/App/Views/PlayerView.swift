import AVKit
import SwiftData
import SwiftUI

struct PlayerView: View {
  let session: Session
  let channel: Channel
  let vodEntry: EPGEntry?

  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext

  @State private var player: AVPlayer?
  @State private var errorMessage: String?
  @State private var singlePlay = SinglePlayService()

  private var isLive: Bool { vodEntry == nil }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      if let player {
        VideoPlayer(player: player)
          .ignoresSafeArea()
      } else if let errorMessage {
        VStack(spacing: 16) {
          Image(systemName: "exclamationmark.triangle")
            .font(.largeTitle)
            .foregroundStyle(.yellow)
          Text(errorMessage)
            .foregroundStyle(.white)
          Button("Dismiss") { dismiss() }
            .buttonStyle(.borderedProminent)
        }
      } else {
        ProgressView("Loading stream...")
          .foregroundStyle(.white)
          .tint(.white)
      }
    }
    .overlay(alignment: .topTrailing) {
      #if !os(tvOS)
        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.title)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .padding()
      #endif
    }
    .task {
      await startPlayback()
    }
    .onDisappear {
      player?.pause()
      player = nil
      Task { await singlePlay.stopPolling() }
    }
  }

  @MainActor
  private func startPlayback() async {
    // Claim single-play
    await singlePlay.startPolling(session: session)

    let url: URL?
    if let entry = vodEntry {
      url = StreamURLBuilder.vodURL(session: session, vodPath: entry.vodPath)
    } else {
      url = StreamURLBuilder.liveURL(session: session, playpath: channel.playpath)
    }

    guard let streamURL = url else {
      errorMessage = "Failed to build stream URL"
      return
    }

    let asset = StreamURLBuilder.asset(
      for: streamURL,
      referer: session.productConfig.referer
    )
    let item = AVPlayerItem(asset: asset)
    let avPlayer = AVPlayer(playerItem: item)

    // Resume VOD from saved position
    if let entry = vodEntry {
      let vid = entry.vodPath
      let descriptor = FetchDescriptor<PlayRecord>(
        predicate: #Predicate { $0.vid == vid }
      )
      if let record = try? modelContext.fetch(descriptor).first, record.positionMs > 0 {
        let resumeTime = CMTime(
          value: Int64(record.positionMs),
          timescale: 1000
        )
        await avPlayer.seek(to: resumeTime)
      }
    }

    self.player = avPlayer
    avPlayer.play()

    // Monitor for playback failures so we show a real error instead of
    // the opaque slashed-play-button icon from VideoPlayer
    while !Task.isCancelled {
      if item.status == .readyToPlay { break }
      if item.status == .failed {
        errorMessage = item.error?.localizedDescription ?? "Playback failed"
        player?.pause()
        player = nil
        return
      }
      try? await Task.sleep(for: .milliseconds(200))
    }
  }
}
