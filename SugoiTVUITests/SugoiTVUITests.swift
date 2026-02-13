import XCTest

final class SugoiTVUITests: XCTestCase {

  @MainActor
  func testChannelListAppearsAfterLogin() throws {
    let (user, pass) = try credentials()
    let app = XCUIApplication()
    app.launch()

    let customerID = app.textFields["Customer ID"]
    #if os(macOS)
    let openSettingsButton = app.buttons["Open Settings…"]
    #endif

    // Wait for the app to finish restoring session or show login
    var ready = false
    for i in 0..<30 {
      #if os(macOS)
      if app.outlines.firstMatch.exists || openSettingsButton.exists { ready = true; break }
      #else
      if app.outlines.firstMatch.exists || customerID.exists { ready = true; break }
      #endif
      if i == 5 {
        print("Poll \(i): outline=\(app.outlines.firstMatch.exists) customerID=\(customerID.exists)")
        print(app.debugDescription)
      }
      Thread.sleep(forTimeInterval: 1)
    }
    XCTAssertTrue(ready, "App should show either channel list or login screen")

    #if os(macOS)
    if openSettingsButton.exists {
      openSettingsButton.tap()
      login(app: app, user: user, pass: pass)
    }
    #else
    if customerID.exists {
      login(app: app, user: user, pass: pass)
    }
    #endif

    // On macOS the sidebar uses a native List which appears as an outline
    let channelList = app.outlines.firstMatch
    XCTAssertTrue(
      channelList.waitForExistence(timeout: 15),
      "Channel list sidebar should appear after login"
    )

    // Verify player view is present
    let playerView = app.otherElements["playerView"]
    XCTAssertTrue(
      playerView.waitForExistence(timeout: 5),
      "Player view should be present after login"
    )

    #if !os(macOS)
    // On iOS/tvOS, verify the channel guide button is visible
    let guideButton = app.buttons["channelGuideButton"]
    XCTAssertTrue(
      guideButton.waitForExistence(timeout: 5),
      "Channel guide button should be visible on iOS/tvOS"
    )
    #endif
  }

  #if os(macOS)
  @MainActor
  func testSettingsContainsSignOut() throws {
    let (user, pass) = try credentials()
    let app = XCUIApplication()
    app.launch()

    let openSettingsButton = app.buttons["Open Settings…"]

    // Wait for the app to finish restoring session or show login/placeholder
    var ready = false
    for _ in 0..<30 {
      if app.outlines.firstMatch.exists || openSettingsButton.exists { ready = true; break }
      Thread.sleep(forTimeInterval: 1)
    }
    XCTAssertTrue(ready, "App should show either channel list or signed-out placeholder")

    if openSettingsButton.exists {
      // Not logged in — open settings and log in there
      openSettingsButton.tap()
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
