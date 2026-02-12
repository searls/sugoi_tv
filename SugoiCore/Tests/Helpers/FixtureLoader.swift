import Foundation

/// Load JSON fixture files from the test bundle's Fixtures directory
public enum FixtureLoader {
  /// Load raw Data from a fixture file
  public static func loadData(_ filename: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: filename, withExtension: nil, subdirectory: "Fixtures") else {
      throw FixtureError.fileNotFound(filename)
    }
    return try Data(contentsOf: url)
  }

  /// Load and decode a JSON fixture into a Decodable type
  public static func loadJSON<T: Decodable>(_ filename: String, as type: T.Type) throws -> T {
    let data = try loadData(filename)
    return try JSONDecoder().decode(type, from: data)
  }

  /// Load a fixture as a UTF-8 string
  public static func loadString(_ filename: String) throws -> String {
    let data = try loadData(filename)
    guard let string = String(data: data, encoding: .utf8) else {
      throw FixtureError.invalidUTF8(filename)
    }
    return string
  }
}

public enum FixtureError: Error, CustomStringConvertible {
  case fileNotFound(String)
  case invalidUTF8(String)

  public var description: String {
    switch self {
    case .fileNotFound(let name): "Fixture file not found: \(name)"
    case .invalidUTF8(let name): "Fixture file is not valid UTF-8: \(name)"
    }
  }
}
