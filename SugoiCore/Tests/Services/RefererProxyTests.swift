import Foundation
import Testing

@testable import SugoiCore

@Suite("RefererProxy")
struct RefererProxyTests {

  // MARK: - URL mapping: buildProxiedURL

  @Test("buildProxiedURL preserves host, port, path, and query")
  func proxiedURLPreservesComponents() {
    let original = URL(string: "http://live.yoitv.com:9083/query/s/abc.M3U8?type=live&token=xyz")!
    let proxied = RefererProxy.buildProxiedURL(original: original, proxyHost: "192.168.1.50", proxyPort: 9234)

    #expect(proxied != nil)
    let str = proxied!.absoluteString
    #expect(str.hasPrefix("http://192.168.1.50:9234/"))
    #expect(str.contains("live.yoitv.com:9083"))
    #expect(str.contains("/query/s/abc.M3U8"))
    #expect(str.contains("type=live"))
    #expect(str.contains("token=xyz"))
  }

  @Test("buildProxiedURL infers port 80 for http")
  func proxiedURLDefaultsPort80() {
    let original = URL(string: "http://cdn.example.com/segment.ts")!
    let proxied = RefererProxy.buildProxiedURL(original: original, proxyHost: "10.0.0.1", proxyPort: 5000)

    let str = proxied!.absoluteString
    #expect(str.contains("cdn.example.com:80"))
  }

  @Test("buildProxiedURL infers port 443 for https")
  func proxiedURLDefaultsPort443() {
    let original = URL(string: "https://secure.example.com/path")!
    let proxied = RefererProxy.buildProxiedURL(original: original, proxyHost: "10.0.0.1", proxyPort: 5000)

    let str = proxied!.absoluteString
    #expect(str.contains("secure.example.com:443"))
  }

  @Test("buildProxiedURL returns nil for schemeless URL")
  func proxiedURLRejectsNoScheme() {
    let original = URL(string: "not-a-url")!
    let proxied = RefererProxy.buildProxiedURL(original: original, proxyHost: "10.0.0.1", proxyPort: 5000)
    #expect(proxied == nil)
  }

  // MARK: - URL mapping: targetURL

  @Test("targetURL reconstructs original URL from proxy path")
  func targetURLReconstruction() {
    let target = RefererProxy.targetURL(
      fromPath: "/live.yoitv.com:9083/query/s/abc.M3U8",
      query: "type=live&token=xyz"
    )

    #expect(target != nil)
    #expect(target!.absoluteString == "http://live.yoitv.com:9083/query/s/abc.M3U8?type=live&token=xyz")
  }

  @Test("targetURL works without query string")
  func targetURLNoQuery() {
    let target = RefererProxy.targetURL(
      fromPath: "/cdn.example.com:80/segments/001.ts",
      query: nil
    )

    #expect(target != nil)
    #expect(target!.absoluteString == "http://cdn.example.com:80/segments/001.ts")
  }

  @Test("targetURL returns nil for empty path")
  func targetURLEmptyPath() {
    let target = RefererProxy.targetURL(fromPath: "/", query: nil)
    #expect(target == nil)
  }

  @Test("targetURL handles leading slash correctly")
  func targetURLLeadingSlash() {
    let target = RefererProxy.targetURL(
      fromPath: "/host:8080/path",
      query: nil
    )
    #expect(target?.absoluteString == "http://host:8080/path")
  }

  // MARK: - Round-trip: buildProxiedURL → targetURL

  @Test("Round-trip: proxy URL → target URL recovers original")
  func roundTrip() {
    let original = URL(string: "http://live.yoitv.com:9083/query/s/test.M3U8?type=live&__cross_domain_user=abc%2Bdef")!
    let proxied = RefererProxy.buildProxiedURL(original: original, proxyHost: "192.168.1.50", proxyPort: 9234)!

    // Extract the path and query as the proxy server would see them
    let path = proxied.path(percentEncoded: false)
    let query = proxied.query(percentEncoded: false)

    let recovered = RefererProxy.targetURL(fromPath: path, query: query)
    #expect(recovered != nil)
    #expect(recovered!.host() == original.host())
    #expect(recovered!.port == original.port)
    #expect(recovered!.path() == original.path())
  }

  // MARK: - HLS manifest rewriting

  @Test("rewriteManifest rewrites absolute URLs to proxy")
  func manifestRewritesAbsoluteURLs() {
    let manifest = """
      #EXTM3U
      #EXT-X-VERSION:3
      #EXT-X-TARGETDURATION:10
      http://cdn.example.com:80/segments/001.ts
      http://cdn.example.com:80/segments/002.ts
      #EXT-X-ENDLIST
      """

    let rewritten = RefererProxy.rewriteManifest(manifest, proxyHost: "10.0.0.1", proxyPort: 5000)

    #expect(rewritten.contains("http://10.0.0.1:5000/cdn.example.com:80/segments/001.ts"))
    #expect(rewritten.contains("http://10.0.0.1:5000/cdn.example.com:80/segments/002.ts"))
    // Tags should be preserved
    #expect(rewritten.contains("#EXTM3U"))
    #expect(rewritten.contains("#EXT-X-VERSION:3"))
    #expect(rewritten.contains("#EXT-X-ENDLIST"))
  }

  @Test("rewriteManifest leaves relative URLs untouched")
  func manifestPreservesRelativeURLs() {
    let manifest = """
      #EXTM3U
      #EXT-X-TARGETDURATION:10
      segments/001.ts
      segments/002.ts
      """

    let rewritten = RefererProxy.rewriteManifest(manifest, proxyHost: "10.0.0.1", proxyPort: 5000)

    #expect(rewritten.contains("segments/001.ts"))
    #expect(rewritten.contains("segments/002.ts"))
    // Should NOT be rewritten (no http:// prefix)
    #expect(!rewritten.contains("10.0.0.1"))
  }

  @Test("rewriteManifest leaves comments untouched")
  func manifestPreservesComments() {
    let manifest = """
      #EXTM3U
      #EXT-X-TARGETDURATION:10
      #EXTINF:10,
      segments/001.ts
      """

    let rewritten = RefererProxy.rewriteManifest(manifest, proxyHost: "10.0.0.1", proxyPort: 5000)

    #expect(rewritten.contains("#EXTM3U"))
    #expect(rewritten.contains("#EXT-X-TARGETDURATION:10"))
    #expect(rewritten.contains("#EXTINF:10,"))
  }

  @Test("rewriteManifest handles mixed absolute and relative URLs")
  func manifestMixedURLs() {
    let manifest = """
      #EXTM3U
      #EXTINF:10,
      http://cdn1.example.com:80/seg1.ts
      #EXTINF:10,
      seg2.ts
      #EXTINF:10,
      http://cdn2.example.com:8080/seg3.ts
      """

    let rewritten = RefererProxy.rewriteManifest(manifest, proxyHost: "10.0.0.1", proxyPort: 5000)

    #expect(rewritten.contains("http://10.0.0.1:5000/cdn1.example.com:80/seg1.ts"))
    #expect(rewritten.contains("seg2.ts"))
    #expect(rewritten.contains("http://10.0.0.1:5000/cdn2.example.com:8080/seg3.ts"))
    // seg2.ts should NOT have the proxy prefix
    let lines = rewritten.split(separator: "\n")
    let seg2Line = lines.first(where: { $0.contains("seg2.ts") })
    #expect(seg2Line == "seg2.ts")
  }

  // MARK: - Redirect rewriting

  @Test("rewriteRedirectLocation rewrites absolute URL through proxy")
  func redirectRewriting() {
    let location = "http://edge.cdn.com:80/redirected/path.m3u8?key=value"
    let rewritten = RefererProxy.rewriteRedirectLocation(
      location,
      proxyHost: "192.168.1.50",
      proxyPort: 9234
    )

    #expect(rewritten != nil)
    #expect(rewritten!.hasPrefix("http://192.168.1.50:9234/"))
    #expect(rewritten!.contains("edge.cdn.com:80"))
    #expect(rewritten!.contains("redirected/path.m3u8"))
  }

  @Test("rewriteRedirectLocation returns nil for unparseable location")
  func redirectRewritingInvalid() {
    let rewritten = RefererProxy.rewriteRedirectLocation(
      "not a valid url with spaces",
      proxyHost: "192.168.1.50",
      proxyPort: 9234
    )
    #expect(rewritten == nil)
  }
}
