import Testing

@testable import SugoiCore

@Suite("String.looksLikePermissionError")
struct LooksLikePermissionErrorTests {
  @Test("Detects 'permission' keyword")
  func detectsPermission() {
    #expect("Access permission denied".looksLikePermissionError)
  }

  @Test("Detects 'authorized' keyword")
  func detectsAuthorized() {
    #expect("Not authorized to access resource".looksLikePermissionError)
  }

  @Test("Detects 'forbidden' keyword")
  func detectsForbidden() {
    #expect("403 Forbidden".looksLikePermissionError)
  }

  @Test("Detects '403' status code")
  func detects403() {
    #expect("HTTP error 403".looksLikePermissionError)
  }

  @Test("Case insensitive matching")
  func caseInsensitive() {
    #expect("PERMISSION DENIED".looksLikePermissionError)
    #expect("Forbidden".looksLikePermissionError)
  }

  @Test("Non-permission errors return false")
  func nonPermissionErrors() {
    #expect(!"Network timeout".looksLikePermissionError)
    #expect(!"File not found".looksLikePermissionError)
    #expect(!"500 Internal Server Error".looksLikePermissionError)
  }
}
