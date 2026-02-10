import Foundation

struct EPGEntry: Identifiable, Sendable {
  let id = UUID()
  let channelId: String
  let startTime: Date
  let title: String
  let vodPath: String

  var hasVOD: Bool { !vodPath.isEmpty }

  static func parse(json: String, channelId: String) -> [EPGEntry] {
    guard let data = json.data(using: .utf8),
      let results = try? JSONDecoder().decode([EPGResult].self, from: data)
    else { return [] }

    return results.map { result in
      EPGEntry(
        channelId: channelId,
        startTime: Date(timeIntervalSince1970: TimeInterval(result.time)),
        title: result.title,
        vodPath: result.path
      )
    }
  }
}
