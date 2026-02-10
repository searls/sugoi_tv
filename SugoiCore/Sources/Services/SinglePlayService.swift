import Foundation

actor SinglePlayService {
  private let api = APIClient.shared
  private var pollingTask: Task<Void, Never>?

  func startPolling(session: Session) {
    stopPolling()
    pollingTask = Task {
      // Claim playback immediately
      _ = try? await api.checkSinglePlay(
        url: session.productConfig.singlePlayURL,
        ua: StreamURLBuilder.platformUA,
        own: true,
        accessToken: session.accessToken
      )

      // Poll every 30 seconds
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(30))
        guard !Task.isCancelled else { break }
        _ = try? await api.checkSinglePlay(
          url: session.productConfig.singlePlayURL,
          ua: StreamURLBuilder.platformUA,
          own: true,
          accessToken: session.accessToken
        )
      }
    }
  }

  func stopPolling() {
    pollingTask?.cancel()
    pollingTask = nil
  }
}
