import XCTest

final class SugoiTVUITests: XCTestCase {

  @MainActor
  func testChannelListAppearsAfterLogin() throws {
    let (user, pass) = try credentials()
    let app = XCUIApplication()
    app.launch()

    let customerID = app.textFields["Customer ID"]

    // Wait for the app to finish restoring session or show login
    var ready = false
    for i in 0..<30 {
      if app.outlines.firstMatch.exists || customerID.exists { ready = true; break }
      if i == 5 {
        print("Poll \(i): outline=\(app.outlines.firstMatch.exists) customerID=\(customerID.exists)")
        print(app.debugDescription)
      }
      Thread.sleep(forTimeInterval: 1)
    }
    XCTAssertTrue(ready, "App should show either channel list or login screen")

    if customerID.exists {
      login(app: app, user: user, pass: pass)
    }

    // On macOS the sidebar uses a native List which appears as an outline
    let channelList = app.outlines.firstMatch
    XCTAssertTrue(
      channelList.waitForExistence(timeout: 15),
      "Channel list sidebar should appear after login"
    )
  }

  #if os(macOS)
  @MainActor
  func testSettingsContainsSignOut() throws {
    let (user, pass) = try credentials()
    let app = XCUIApplication()
    app.launch()

    let customerID = app.textFields["Customer ID"]

    // Wait for the app to finish restoring session or show login
    var ready = false
    for _ in 0..<30 {
      if app.outlines.firstMatch.exists || customerID.exists { ready = true; break }
      Thread.sleep(forTimeInterval: 1)
    }
    XCTAssertTrue(ready, "App should show either channel list or login screen")

    if customerID.exists {
      login(app: app, user: user, pass: pass)
      let channelList = app.outlines.firstMatch
      XCTAssertTrue(channelList.waitForExistence(timeout: 15), "Should be logged in")
    }

    // Open Settings via Cmd+,
    app.typeKey(",", modifierFlags: .command)

    let signOut = app.buttons["signOutButton"]
    XCTAssertTrue(
      signOut.waitForExistence(timeout: 5),
      "Settings window should contain Sign Out button"
    )
  }
  #endif

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
