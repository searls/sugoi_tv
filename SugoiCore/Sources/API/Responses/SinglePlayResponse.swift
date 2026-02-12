import Foundation

public struct SinglePlayResponse: Codable, Sendable {
  public let own: Bool
  public let code: String?
}
