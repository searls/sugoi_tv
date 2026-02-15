import XCTest

/// Exercises the full navigation + playback flow using fixture data (no network, no credentials).
/// Launch argument `-UITestFixtureMode` causes the app to render `FixtureModeRootView`, which
/// feeds captured JSON fixtures through a fake API client. Playback uses a bundled test-video.mp4.
final class FixtureModeUITests: XCTestCase {

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testChannelListToProgramListToPlayback() throws {
    let app = XCUIApplication()
    app.launchArguments = [
      "-UITestFixtureMode",
      "-lastChannelId", "",
      "-sidebarVisible", "true",
      "-lastActiveTimestamp", "0",
    ]
    app.launch()

    // --- Step 1: Wait for program list (auto-select pushes into it) ---

    XCTAssertTrue(
      findElement(app, identifier: "programList"),
      "Program list should appear after auto-selection"
    )

    // --- Step 2: Verify playback ---

    let playerView = app.otherElements["playerView"]
    XCTAssertTrue(
      playerView.waitForExistence(timeout: 10),
      "Player view should exist"
    )

    #if os(macOS)
    // Mac: auto-play fires on channel selection (non-compact layout)
    assertPlayerReaches(state: "playing", element: playerView, timeout: 15)
    #else
    // iOS/tvOS: check if already playing (iPad regular) or trigger manually (iPhone compact)
    if playerView.value as? String != "playing" {
      let vodButton = app.buttons.matching(
        NSPredicate(format: "identifier BEGINSWITH 'vodProgram_'")
      ).firstMatch
      let liveButton = app.buttons["playLiveButton"]

      if vodButton.waitForExistence(timeout: 5) {
        vodButton.tap()
      } else if liveButton.waitForExistence(timeout: 3) {
        liveButton.tap()
      } else {
        XCTFail("No playable program found in fixture data")
        return
      }
      assertPlayerReaches(state: "playing", element: playerView, timeout: 15)
    }
    #endif

    // --- Step 3: Navigate back to channel list ---

    #if os(macOS)
    // macOS sidebar has a manual "Channels" back button
    let backButton = app.buttons["Channels"]
    XCTAssertTrue(
      backButton.waitForExistence(timeout: 5),
      "Channels back button should exist in sidebar toolbar"
    )
    backButton.tap()
    #else
    // iOS: go back via NavigationStack back button.
    // On compact layout the detail column may be showing — first check if
    // the navigation bar back button is already visible, otherwise look for
    // the sidebar toggle provided by NavigationSplitView.
    let navBackButton = app.navigationBars.buttons.firstMatch
    if navBackButton.waitForExistence(timeout: 5) {
      navBackButton.tap()
      // If we were in the detail column (compact), a second tap may be
      // needed to pop from program list back to channel list.
      if !findElement(app, identifier: "channelList", timeout: 3) {
        let secondBack = app.navigationBars.buttons.firstMatch
        if secondBack.waitForExistence(timeout: 3) {
          secondBack.tap()
        }
      }
    }
    #endif

    // --- Step 4: Verify channel list is visible ---

    XCTAssertTrue(
      findElement(app, identifier: "channelList"),
      "Channel list should appear after navigating back"
    )

    // Verify a known fixture channel name is visible
    let nhk = app.staticTexts["NHK総合・東京"].firstMatch
    XCTAssertTrue(
      nhk.waitForExistence(timeout: 5),
      "NHK channel should be visible in channel list"
    )
  }

  // MARK: - Helpers

  /// Finds any element with the given accessibility identifier, regardless of element type.
  private func findElement(
    _ app: XCUIApplication,
    identifier: String,
    timeout: TimeInterval = 15
  ) -> Bool {
    let predicate = NSPredicate(format: "identifier == %@", identifier)
    let element = app.descendants(matching: .any).matching(predicate).firstMatch
    return element.waitForExistence(timeout: timeout)
  }

  /// Waits for the player view's accessibility value to reach the expected state.
  private func assertPlayerReaches(
    state: String,
    element: XCUIElement,
    timeout: TimeInterval
  ) {
    let predicate = NSPredicate(format: "value == %@", state)
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
    let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
    XCTAssertEqual(
      result, .completed,
      "Player should reach '\(state)' state (current: \(element.value ?? "nil"))"
    )
  }
}
