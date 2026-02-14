#if os(macOS)
import Foundation
import Testing
@testable import SugoiCore

@Suite("SidebarPersistence")
struct SidebarPersistenceTests {
  let now: TimeInterval = 1_700_000_000 // arbitrary fixed "now"
  let threshold: TimeInterval = 12 * 3600

  // MARK: - Recent session (within threshold)

  @Test("Recent session with sidebar visible → stays visible")
  func recentSessionSidebarVisible() {
    let lastActive = now - 3600 // 1 hour ago
    let result = SidebarPersistence.shouldShowSidebar(
      wasSidebarVisible: true,
      lastActiveTimestamp: lastActive,
      now: now,
      staleThreshold: threshold
    )
    #expect(result == true)
  }

  @Test("Recent session with sidebar collapsed → stays collapsed")
  func recentSessionSidebarCollapsed() {
    let lastActive = now - 3600 // 1 hour ago
    let result = SidebarPersistence.shouldShowSidebar(
      wasSidebarVisible: false,
      lastActiveTimestamp: lastActive,
      now: now,
      staleThreshold: threshold
    )
    #expect(result == false)
  }

  // MARK: - Stale session (beyond threshold)

  @Test("Stale session → always shows sidebar regardless of saved state")
  func staleSessionAlwaysShowsSidebar() {
    let lastActive = now - (13 * 3600) // 13 hours ago
    let collapsed = SidebarPersistence.shouldShowSidebar(
      wasSidebarVisible: false,
      lastActiveTimestamp: lastActive,
      now: now,
      staleThreshold: threshold
    )
    #expect(collapsed == true)

    let visible = SidebarPersistence.shouldShowSidebar(
      wasSidebarVisible: true,
      lastActiveTimestamp: lastActive,
      now: now,
      staleThreshold: threshold
    )
    #expect(visible == true)
  }

  // MARK: - Edge cases

  @Test("Exactly at threshold boundary → shows sidebar")
  func exactlyAtThreshold() {
    let lastActive = now - threshold // exactly 12 hours
    let result = SidebarPersistence.shouldShowSidebar(
      wasSidebarVisible: false,
      lastActiveTimestamp: lastActive,
      now: now,
      staleThreshold: threshold
    )
    #expect(result == true)
  }

  @Test("First launch (zero timestamp) → shows sidebar")
  func firstLaunch() {
    let result = SidebarPersistence.shouldShowSidebar(
      wasSidebarVisible: false,
      lastActiveTimestamp: 0,
      now: now,
      staleThreshold: threshold
    )
    #expect(result == true)
  }

  @Test("Just under threshold → respects saved state")
  func justUnderThreshold() {
    let lastActive = now - threshold + 1 // 1 second under
    let result = SidebarPersistence.shouldShowSidebar(
      wasSidebarVisible: false,
      lastActiveTimestamp: lastActive,
      now: now,
      staleThreshold: threshold
    )
    #expect(result == false)
  }
}
#endif
