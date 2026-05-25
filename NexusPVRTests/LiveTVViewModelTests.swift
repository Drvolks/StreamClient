//
//  LiveTVViewModelTests.swift
//  NexusPVRTests
//
//  Tests for LiveTVViewModel filteredChannels, currentProgram, and error handling.
//

import Testing
import Foundation
@testable import NextPVR

@MainActor
struct LiveTVViewModelTests {

    private func makeClient() -> NextPVRClient {
        NextPVRClient(config: ServerConfig(host: "demo", pin: "", useHTTPS: false))
    }

    @Test("filteredChannels returns all when search is empty")
    func filteredChannelsAllWhenEmptySearch() {
        let vm = LiveTVViewModel(client: makeClient())
        vm.channels = [
            Channel(id: 1, name: "ABC", number: 1),
            Channel(id: 2, name: "NBC", number: 2),
            Channel(id: 3, name: "CBS", number: 3)
        ]
        vm.searchText = ""
        #expect(vm.filteredChannels.count == 3)
    }

    @Test("filteredChannels filters by name case-insensitively")
    func filteredChannelsByName() {
        let vm = LiveTVViewModel(client: makeClient())
        vm.channels = [
            Channel(id: 1, name: "ABC News", number: 1),
            Channel(id: 2, name: "NBC Sports", number: 2),
            Channel(id: 3, name: "CBS Drama", number: 3)
        ]
        vm.searchText = "news"
        #expect(vm.filteredChannels.count == 1)
        #expect(vm.filteredChannels.first?.name == "ABC News")
    }

    @Test("filteredChannels filters by channel number")
    func filteredChannelsByNumber() {
        let vm = LiveTVViewModel(client: makeClient())
        vm.channels = [
            Channel(id: 1, name: "ABC", number: 101),
            Channel(id: 2, name: "NBC", number: 202),
            Channel(id: 3, name: "CBS", number: 303)
        ]
        vm.searchText = "20"
        #expect(vm.filteredChannels.count == 1)
        #expect(vm.filteredChannels.first?.number == 202)
    }

    @Test("filteredChannels returns empty when no match")
    func filteredChannelsNoMatch() {
        let vm = LiveTVViewModel(client: makeClient())
        vm.channels = [
            Channel(id: 1, name: "ABC", number: 1)
        ]
        vm.searchText = "XYZNOTEXIST"
        #expect(vm.filteredChannels.isEmpty)
    }

    @Test("loadChannels sets error when not configured")
    func loadChannelsNotConfigured() async {
        let client = NextPVRClient(config: ServerConfig(host: "", pin: "", useHTTPS: false))
        let vm = LiveTVViewModel(client: client)
        await vm.loadChannels()
        #expect(vm.error != nil)
        #expect(vm.isLoading == false)
    }

    @Test("currentProgram returns nil for channel with no data")
    func currentProgramReturnsNil() {
        let vm = LiveTVViewModel(client: makeClient())
        let ch = Channel(id: 99, name: "Unknown", number: 99)
        #expect(vm.currentProgram(for: ch) == nil)
    }

    @Test("currentProgram returns program when data is set")
    func currentProgramReturnsProgram() {
        let vm = LiveTVViewModel(client: makeClient())
        let ch = Channel(id: 1, name: "Test", number: 1)
        let now = Int(Date().timeIntervalSince1970)
        let program = Program(
            id: 100,
            name: "News",
            subtitle: nil,
            desc: nil,
            start: now - 1800,
            end: now + 1800,
            genres: nil,
            channelId: 1
        )
        vm.currentPrograms = [1: program]
        #expect(vm.currentProgram(for: ch)?.id == 100)
        #expect(vm.currentProgram(for: ch)?.name == "News")
    }

    @Test("streamURL returns a URL from demo client")
    func streamURLReturnsURL() async throws {
        let client = NextPVRClient(config: ServerConfig(host: "demo", pin: "", useHTTPS: false))
        let vm = LiveTVViewModel(client: client)
        let ch = Channel(id: 1, name: "Test", number: 1)
        let url = try await vm.streamURL(for: ch)
        #expect(url.absoluteString.hasSuffix(".mp4"))
    }

    @Test("isLoading defaults to false")
    func isLoadingDefaultsFalse() {
        let vm = LiveTVViewModel(client: makeClient())
        #expect(vm.isLoading == false)
    }

    @Test("error defaults to nil")
    func errorDefaultsToNil() {
        let vm = LiveTVViewModel(client: makeClient())
        #expect(vm.error == nil)
    }

    @Test("searchText defaults to empty")
    func searchTextDefaultsEmpty() {
        let vm = LiveTVViewModel(client: makeClient())
        #expect(vm.searchText.isEmpty)
    }

    @Test("channels defaults to empty")
    func channelsDefaultsEmpty() {
        let vm = LiveTVViewModel(client: makeClient())
        #expect(vm.channels.isEmpty)
    }
}
