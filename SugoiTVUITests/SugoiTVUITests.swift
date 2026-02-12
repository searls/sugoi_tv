import XCTest

final class SugoiTVUITests: XCTestCase {

  @MainActor
  func testGuideButtonOpensChannelGuide() throws {
    let (user, pass) = try credentials()
    let app = XCUIApplication()
    app.launch()

    let guideButton = app.buttons["channelGuideButton"]
    if !guideButton.waitForExistence(timeout: 5) {
      login(app: app, user: user, pass: pass)
      XCTAssertTrue(guideButton.waitForExistence(timeout: 15), "Guide button should appear after login")
    }

    guideButton.tap()

    // Look for the Close button that appears in the channel guide sheet toolbar
    let closeButton = app.buttons["Close"]
    XCTAssertTrue(closeButton.waitForExistence(timeout: 5), "Channel Guide sheet should open with Close button")
  }

  // MARK: - Helpers

  private func login(app: XCUIApplication, user: String, pass: String) {
    let customerID = app.textFields["Customer ID"]
    guard customerID.waitForExistence(timeout: 10) else {
      XCTFail("Login screen not found")
      return
    }
    customerID.tap()
    customerID.typeText(user)
    let password = app.secureTextFields["Password"]
    password.tap()
    password.typeText(pass)
    app.buttons["Sign In"].tap()
  }

  private func credentials() throws -> (String, String) {
    let path = "/tmp/sugoi_test_credentials"
    guard let data = FileManager.default.contents(atPath: path),
          let content = String(data: data, encoding: .utf8) else {
      throw XCTSkip("No credentials file at \(path)")
    }
    let lines = content.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n")
    guard lines.count >= 2 else {
      throw XCTSkip("Credentials file needs two lines: USER and PASS")
    }
    return (String(lines[0]), String(lines[1]))
  }
}
