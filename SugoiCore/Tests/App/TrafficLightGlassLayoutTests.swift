#if os(macOS)
import SwiftUI
import Testing

@testable import SugoiCore

@Suite("TrafficLightGlassLayout")
struct TrafficLightGlassLayoutTests {

  @Test("visible when sidebar is hidden (detailOnly)")
  func visibleWhenDetailOnly() {
    #expect(TrafficLightGlassLayout.isVisible(.detailOnly) == true)
  }

  @Test("hidden when sidebar is showing (doubleColumn)")
  func hiddenWhenDoubleColumn() {
    #expect(TrafficLightGlassLayout.isVisible(.doubleColumn) == false)
  }

  @Test("hidden when all columns are visible")
  func hiddenWhenAll() {
    #expect(TrafficLightGlassLayout.isVisible(.all) == false)
  }

  @Test("hidden for automatic visibility")
  func hiddenWhenAutomatic() {
    #expect(TrafficLightGlassLayout.isVisible(.automatic) == false)
  }
}
#endif
