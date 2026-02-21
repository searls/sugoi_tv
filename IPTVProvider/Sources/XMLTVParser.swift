import Foundation

/// A single program parsed from an XMLTV guide.
public struct XMLTVProgram: Sendable {
  public let channelID: String
  public let start: Date
  public let title: String
}

/// Parses XMLTV (XML) program guide data using Foundation's streaming XMLParser.
public struct XMLTVParser: Sendable {
  /// Parse XMLTV data into a dictionary keyed by channel ID.
  public static func parse(_ data: Data) -> [String: [XMLTVProgram]] {
    let delegate = XMLTVParserDelegate()
    let parser = XMLParser(data: data)
    parser.delegate = delegate
    parser.parse()
    return delegate.programs
  }

  /// DateFormatter for XMLTV timestamp format: "YYYYMMDDHHmmss +0000"
  static let timestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMddHHmmss Z"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter
  }()
}

// MARK: - XMLParser delegate

private final class XMLTVParserDelegate: NSObject, XMLParserDelegate {
  var programs: [String: [XMLTVProgram]] = [:]

  private var currentChannelID: String?
  private var currentStart: Date?
  private var currentTitle: String?
  private var currentElement: String?
  private var currentText = ""

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName: String?,
    attributes: [String: String]
  ) {
    currentElement = elementName

    if elementName == "programme" {
      currentChannelID = attributes["channel"]
      if let startStr = attributes["start"] {
        currentStart = XMLTVParser.timestampFormatter.date(from: startStr)
      }
      currentTitle = nil
    } else if elementName == "title" {
      currentText = ""
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    if currentElement == "title" {
      currentText += string
    }
  }

  func parser(
    _ parser: XMLParser,
    didEndElement elementName: String,
    namespaceURI: String?,
    qualifiedName: String?
  ) {
    if elementName == "title" {
      currentTitle = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
    } else if elementName == "programme" {
      if let channelID = currentChannelID,
         let start = currentStart,
         let title = currentTitle, !title.isEmpty {
        let program = XMLTVProgram(channelID: channelID, start: start, title: title)
        programs[channelID, default: []].append(program)
      }
      currentChannelID = nil
      currentStart = nil
      currentTitle = nil
    }

    if elementName == currentElement {
      currentElement = nil
    }
  }
}
