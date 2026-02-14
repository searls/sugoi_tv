import Foundation
import Testing

@testable import SugoiCore

@Suite("ChannelListViewModel")
struct ChannelListViewModelTests {
  static let channelsJSON = """
    {
      "result": [
        {"id": "CH1", "name": "NHK総合", "description": "NHK General", "tags": "$LIVE_CAT_関東", "no": 1, "playpath": "/nhk", "running": 1},
        {"id": "CH2", "name": "テレビ朝日", "description": "TV Asahi", "tags": "$LIVE_CAT_関東", "no": 2, "playpath": "/tvasahi"},
        {"id": "CH3", "name": "MBS毎日放送", "tags": "$LIVE_CAT_関西", "no": 3, "playpath": "/mbs"}
      ],
      "code": "OK"
    }
    """

  static var testConfig: ProductConfig {
    ProductConfig(
      vmsHost: "http://live.yoitv.com:9083",
      vmsVodHost: nil, vmsUid: "UID", vmsLiveCid: "CID",
      vmsReferer: "http://play.yoitv.com", epgDays: nil, single: nil,
      vmsChannelListHost: nil, vmsLiveHost: nil, vmsRecordHost: nil, vmsLiveUid: nil
    )
  }

  private func makeMock() -> MockHTTPSession {
    let mock = MockHTTPSession()
    mock.requestHandler = { _ in
      let response = HTTPURLResponse(
        url: URL(string: "http://test.com")!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(Self.channelsJSON.utf8))
    }
    return mock
  }

  @Test("Loads channels and groups them")
  @MainActor
  func loadChannels() async {
    let mock = makeMock()
    let service = ChannelService(apiClient: APIClient(session: mock.session))
    let vm = ChannelListViewModel(channelService: service, config: Self.testConfig)

    await vm.loadChannels()

    #expect(vm.isLoading == false)
    #expect(vm.errorMessage == nil)
    #expect(vm.channelGroups.count == 2) // 関東 and 関西
    #expect(vm.channelGroups[0].category == "関東")
    #expect(vm.channelGroups[0].channels.count == 2)
    #expect(vm.channelGroups[1].category == "関西")
  }

  @Test("Search filters channels by name")
  @MainActor
  func searchByName() async {
    let mock = makeMock()
    let service = ChannelService(apiClient: APIClient(session: mock.session))
    let vm = ChannelListViewModel(channelService: service, config: Self.testConfig)

    await vm.loadChannels()
    vm.searchText = "NHK"

    let filtered = vm.filteredGroups
    #expect(filtered.count == 1)
    #expect(filtered[0].channels.count == 1)
    #expect(filtered[0].channels[0].name == "NHK総合")
  }

  @Test("Search filters channels by description")
  @MainActor
  func searchByDescription() async {
    let mock = makeMock()
    let service = ChannelService(apiClient: APIClient(session: mock.session))
    let vm = ChannelListViewModel(channelService: service, config: Self.testConfig)

    await vm.loadChannels()
    vm.searchText = "Asahi"

    let filtered = vm.filteredGroups
    #expect(filtered.count == 1)
    #expect(filtered[0].channels[0].name == "テレビ朝日")
  }

  @Test("Empty search returns all groups")
  @MainActor
  func emptySearchReturnsAll() async {
    let mock = makeMock()
    let service = ChannelService(apiClient: APIClient(session: mock.session))
    let vm = ChannelListViewModel(channelService: service, config: Self.testConfig)

    await vm.loadChannels()
    vm.searchText = ""

    #expect(vm.filteredGroups.count == vm.channelGroups.count)
  }

  @Test("Config exposes channelListHost for thumbnail URL construction")
  @MainActor
  func thumbnailURLFromConfig() async {
    let mock = makeMock()
    let service = ChannelService(apiClient: APIClient(session: mock.session))
    let vm = ChannelListViewModel(channelService: service, config: Self.testConfig)

    await vm.loadChannels()

    let channel = vm.channelGroups[0].channels[0]
    let url = StreamURLBuilder.thumbnailURL(
      channelListHost: vm.config.channelListHost,
      playpath: channel.playpath
    )
    #expect(url != nil)
    let str = url!.absoluteString
    #expect(str == "http://live.yoitv.com:9083/nhk.jpg?type=live&thumbnail=thumbnail_small.jpg")
  }

  @Test("Each channel produces a distinct thumbnail URL")
  @MainActor
  func distinctThumbnailURLsPerChannel() async {
    let mock = makeMock()
    let service = ChannelService(apiClient: APIClient(session: mock.session))
    let vm = ChannelListViewModel(channelService: service, config: Self.testConfig)

    await vm.loadChannels()

    let allChannels = vm.channelGroups.flatMap(\.channels)
    let urls = allChannels.compactMap {
      StreamURLBuilder.thumbnailURL(
        channelListHost: vm.config.channelListHost,
        playpath: $0.playpath
      )
    }
    #expect(urls.count == allChannels.count)
    #expect(Set(urls).count == urls.count) // all unique
  }

  @Test("ChannelRow receives thumbnail URL matching its channel playpath")
  @MainActor
  func channelRowReceivesThumbnailURL() async {
    let mock = makeMock()
    let service = ChannelService(apiClient: APIClient(session: mock.session))
    let vm = ChannelListViewModel(channelService: service, config: Self.testConfig)

    await vm.loadChannels()

    let channel = vm.channelGroups[0].channels[0]
    let expectedURL = StreamURLBuilder.thumbnailURL(
      channelListHost: vm.config.channelListHost,
      playpath: channel.playpath
    )
    let row = ChannelRow(channel: channel, thumbnailURL: expectedURL)

    #expect(row.thumbnailURL != nil)
    #expect(row.thumbnailURL == expectedURL)
    #expect(row.thumbnailURL!.absoluteString.contains(channel.playpath))
    #expect(row.thumbnailURL!.absoluteString.contains("thumbnail_small.jpg"))
  }

  @Test("ChannelRow handles nil thumbnail URL")
  @MainActor
  func channelRowNilThumbnail() async {
    let mock = makeMock()
    let service = ChannelService(apiClient: APIClient(session: mock.session))
    let vm = ChannelListViewModel(channelService: service, config: Self.testConfig)

    await vm.loadChannels()

    let channel = vm.channelGroups[0].channels[0]
    let row = ChannelRow(channel: channel, thumbnailURL: nil)

    #expect(row.thumbnailURL == nil)
  }

  @Test("Load failure sets error message")
  @MainActor
  func loadFailure() async {
    let mock = MockHTTPSession()
    mock.requestHandler = { _ in
      throw URLError(.notConnectedToInternet)
    }

    let service = ChannelService(apiClient: APIClient(session: mock.session))
    let vm = ChannelListViewModel(channelService: service, config: Self.testConfig)

    await vm.loadChannels()

    #expect(vm.isLoading == false)
    #expect(vm.errorMessage == "Failed to load channels.")
    #expect(vm.channelGroups.isEmpty)
  }
}

// MARK: - Channel cache tests

@Suite("ChannelListViewModel.cache")
struct ChannelListViewModelCacheTests {
  static var testConfig: ProductConfig {
    ChannelListViewModelTests.testConfig
  }

  static let channelsJSON = ChannelListViewModelTests.channelsJSON

  /// Creates an isolated UserDefaults suite and returns it along with a cleanup closure.
  private func makeTestDefaults() -> UserDefaults {
    let suiteName = "com.sugoi.test.channelCache.\(UUID().uuidString)"
    return UserDefaults(suiteName: suiteName)!
  }

  private func makeMock() -> MockHTTPSession {
    let mock = MockHTTPSession()
    mock.requestHandler = { _ in
      let response = HTTPURLResponse(
        url: URL(string: "http://test.com")!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(Self.channelsJSON.utf8))
    }
    return mock
  }

  @Test("loadChannels caches channels, loadCachedChannels restores them")
  @MainActor
  func cacheRoundTrip() async {
    let defaults = makeTestDefaults()
    let mock = makeMock()
    let service = ChannelService(apiClient: APIClient(session: mock.session))

    // Fetch from network → should cache
    let vm1 = ChannelListViewModel(channelService: service, config: Self.testConfig, defaults: defaults)
    await vm1.loadChannels()
    #expect(vm1.channelGroups.count == 2)

    // New VM, same defaults → should restore from cache without network
    let failMock = MockHTTPSession()
    failMock.requestHandler = { _ in
      Issue.record("Should not make network requests when loading from cache")
      throw URLError(.badURL)
    }
    let service2 = ChannelService(apiClient: APIClient(session: failMock.session))
    let vm2 = ChannelListViewModel(channelService: service2, config: Self.testConfig, defaults: defaults)
    vm2.loadCachedChannels()

    #expect(vm2.channelGroups.count == 2)
    #expect(vm2.channelGroups[0].category == "関東")
    #expect(vm2.channelGroups[0].channels.count == 2)
    #expect(vm2.channelGroups[1].category == "関西")
  }

  @Test("loadCachedChannels is a no-op when cache is empty")
  @MainActor
  func cacheMiss() {
    let defaults = makeTestDefaults()
    let mock = MockHTTPSession()
    let service = ChannelService(apiClient: APIClient(session: mock.session))
    let vm = ChannelListViewModel(channelService: service, config: Self.testConfig, defaults: defaults)

    vm.loadCachedChannels()

    #expect(vm.channelGroups.isEmpty)
  }

  @Test("Cached channels preserve channel data accurately")
  @MainActor
  func cachePreservesData() async {
    let defaults = makeTestDefaults()
    let mock = makeMock()
    let service = ChannelService(apiClient: APIClient(session: mock.session))

    let vm1 = ChannelListViewModel(channelService: service, config: Self.testConfig, defaults: defaults)
    await vm1.loadChannels()

    let vm2 = ChannelListViewModel(channelService: service, config: Self.testConfig, defaults: defaults)
    vm2.loadCachedChannels()

    let original = vm1.channelGroups.flatMap(\.channels)
    let cached = vm2.channelGroups.flatMap(\.channels)
    #expect(original.count == cached.count)
    for (orig, cache) in zip(original, cached) {
      #expect(orig.id == cache.id)
      #expect(orig.name == cache.name)
      #expect(orig.playpath == cache.playpath)
    }
  }
}
