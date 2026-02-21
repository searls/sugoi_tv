import Foundation

/// A single channel parsed from an M3U playlist.
public struct M3UChannel: Sendable {
  public let id: String
  public let name: String
  public let logoURL: URL?
  public let group: String
  public let channelNumber: Int
  public let streamURL: URL
}

/// Parses M3U/M3U8 playlist files into structured channel data.
public struct M3UParser: Sendable {
  /// Parse an M3U playlist string into channels and an optional EPG URL.
  public static func parse(_ content: String) -> (channels: [M3UChannel], epgURL: URL?) {
    let lines = content.components(separatedBy: .newlines)
    var epgURL: URL?
    var channels: [M3UChannel] = []
    var autoNumber = 1

    // Extract EPG URL from #EXTM3U header
    if let header = lines.first, header.hasPrefix("#EXTM3U") {
      epgURL = extractAttribute("x-tvg-url", from: header).flatMap(URL.init(string:))
    }

    var i = 0
    while i < lines.count {
      let line = lines[i].trimmingCharacters(in: .whitespaces)
      guard line.hasPrefix("#EXTINF:") else {
        i += 1
        continue
      }

      // Parse #EXTINF line
      let extinf = line

      // Find stream URL on next non-empty, non-comment line
      var streamURLString: String?
      var j = i + 1
      while j < lines.count {
        let nextLine = lines[j].trimmingCharacters(in: .whitespaces)
        j += 1
        if nextLine.isEmpty || nextLine.hasPrefix("#") { continue }
        streamURLString = nextLine
        break
      }

      guard let urlString = streamURLString, let streamURL = URL(string: urlString) else {
        i = j
        continue
      }

      let id = extractAttribute("tvg-id", from: extinf) ?? "auto-\(autoNumber)"
      let name = extractDisplayTitle(from: extinf)
      let logoURL = extractAttribute("tvg-logo", from: extinf).flatMap(URL.init(string:))
      let group = extractAttribute("group-title", from: extinf) ?? "Uncategorized"
      let channelNumber = extractAttribute("tvg-chno", from: extinf).flatMap(Int.init) ?? autoNumber

      channels.append(M3UChannel(
        id: id,
        name: name,
        logoURL: logoURL,
        group: group,
        channelNumber: channelNumber,
        streamURL: streamURL
      ))

      autoNumber += 1
      i = j
    }

    return (channels, epgURL)
  }

  /// Extract a quoted attribute value from an EXTINF line.
  /// Matches: key="value"
  static func extractAttribute(_ key: String, from line: String) -> String? {
    // Pattern: key="value" (value can be empty)
    let pattern = "\(key)=\"([^\"]*)\""
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
          let range = Range(match.range(at: 1), in: line)
    else { return nil }
    let value = String(line[range])
    return value.isEmpty ? nil : value
  }

  /// Extract the display title (text after the last comma in an EXTINF line).
  static func extractDisplayTitle(from line: String) -> String {
    // The display name comes after the last comma
    guard let commaIndex = line.lastIndex(of: ",") else { return "Unknown" }
    let title = String(line[line.index(after: commaIndex)...]).trimmingCharacters(in: .whitespaces)
    return title.isEmpty ? "Unknown" : title
  }
}
