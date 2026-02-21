import Foundation
import Testing

@testable import SugoiCore

@Suite("ChannelListViewModel")
struct ChannelListViewModelTests {
  static let testChannels: [ChannelDTO] = {
    let json = Data("""
    {
      "result": [
        {"id": "CH1", "name": "NHK総合", "description": "NHK General", "tags": "$LIVE_CAT_関東", "no": 1, "playpath": "/nhk", "running": 1},
        {"id": "CH2", "name": "テレビ朝日", "description": "TV Asahi", "tags": "$LIVE_CAT_関東", "no": 2, "playpath": "/tvasahi"},
        {"id": "CH3", "name": "MBS毎日放送", "tags": "$LIVE_CAT_関西", "no": 3, "playpath": "/mbs"}
      ],
      "code": "OK"
    }
    """.utf8)
    struct _R: Decodable { let result: [ChannelDTO] }
    return try! JSONDecoder().decode(_R.self, from: json).result
  }()

  @MainActor
  private func makeVM(channels: [ChannelDTO] = testChannels) -> (MockTVProvider, ChannelListViewModel) {
    let mock = MockTVProvider(isAuthenticated: true, channels: channels)
    let vm = ChannelListViewModel(provider: mock)
    return (mock, vm)
  }

  @Test("Loads channels and groups them")
  @MainActor
  func loadChannels() async {
    let (_, vm) = makeVM()

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
    let (_, vm) = makeVM()

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
    let (_, vm) = makeVM()

    await vm.loadChannels()
    vm.searchText = "Asahi"

    let filtered = vm.filteredGroups
    #expect(filtered.count == 1)
    #expect(filtered[0].channels[0].name == "テレビ朝日")
  }

  @Test("Empty search returns all groups")
  @MainActor
  func emptySearchReturnsAll() async {
    let (_, vm) = makeVM()

    await vm.loadChannels()
    vm.searchText = ""

    #expect(vm.filteredGroups.count == vm.channelGroups.count)
  }

  @Test("thumbnailURL delegates to provider")
  @MainActor
  func thumbnailURLDelegatesToProvider() async {
    let (mock, vm) = makeVM()
    let expectedURL = URL(string: "http://test.com/thumb.jpg")!
    mock.setThumbnailHandler { _ in expectedURL }

    await vm.loadChannels()

    let channel = vm.channelGroups[0].channels[0]
    let url = vm.thumbnailURL(for: channel)
    #expect(url == expectedURL)
  }

  @Test("thumbnailURL returns nil when provider returns nil")
  @MainActor
  func thumbnailURLNil() async {
    let (_, vm) = makeVM()

    await vm.loadChannels()

    let channel = vm.channelGroups[0].channels[0]
    let url = vm.thumbnailURL(for: channel)
    #expect(url == nil)
  }

  @Test("ChannelRow handles nil thumbnail URL")
  @MainActor
  func channelRowNilThumbnail() async {
    let (_, vm) = makeVM()

    await vm.loadChannels()

    let channel = vm.channelGroups[0].channels[0]
    let row = ChannelRow(channel: channel, thumbnailURL: nil)

    #expect(row.thumbnailURL == nil)
  }

  @Test("Load failure sets error message")
  @MainActor
  func loadFailure() async {
    // Provider with no channels that throws on fetch
    let mock = MockTVProvider(isAuthenticated: true)
    mock.setShouldFailFetch(true)
    let vm = ChannelListViewModel(provider: mock)

    await vm.loadChannels()

    #expect(vm.isLoading == false)
    #expect(vm.errorMessage == "Failed to load channels.")
    #expect(vm.channelGroups.isEmpty)
  }
}
