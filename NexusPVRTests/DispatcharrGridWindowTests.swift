//
//  DispatcharrGridWindowTests.swift
//  NexusPVRTests
//
//  Tests for the windowed Dispatcharr EPG grid (#157): request building,
//  support detection, and the check that a response kept to its window.
//

import Testing
import Foundation
@testable import NextPVR

struct DispatcharrGridWindowTests {

    private let base = "http://dispatcharr.local:9191"
    private let windowStart = Date(timeIntervalSince1970: 1_771_027_200) // 2026-02-14T00:00:00Z

    private var window: DateInterval {
        DateInterval(start: windowStart, duration: 24 * 3600)
    }

    private func query(_ url: URL?) -> [String: String] {
        let items = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }

    private func program(id: String, start: String, end: String) throws -> DispatcharrProgram {
        let json = #"{"id":\#(id),"start_time":"\#(start)","end_time":"\#(end)","title":"Show","tvg_id":"a"}"#
        return try JSONDecoder().decode(DispatcharrProgram.self, from: Data(json.utf8))
    }

    // MARK: - Request building

    @Test("No window and no profile is the bare grid URL older servers know")
    func defaultWindowURL() {
        let url = DispatcharrGridWindow.url(baseURL: base, window: nil, profileId: nil)
        #expect(url?.absoluteString == "\(base)/api/epg/grid/")
    }

    @Test("A window is sent as ISO 8601 UTC start and end")
    func windowURL() {
        let url = DispatcharrGridWindow.url(baseURL: base, window: window, profileId: nil)
        #expect(url?.absoluteString.hasPrefix("\(base)/api/epg/grid/?") == true)
        #expect(query(url) == ["start": "2026-02-14T00:00:00Z", "end": "2026-02-15T00:00:00Z"])
    }

    @Test("The guide's profile is passed along with the window")
    func profileURL() {
        let url = DispatcharrGridWindow.url(baseURL: base, window: window, profileId: 7)
        #expect(query(url)["channel_profile_id"] == "7")
        #expect(query(url)["start"] == "2026-02-14T00:00:00Z")

        let defaultWindow = DispatcharrGridWindow.url(baseURL: base, window: nil, profileId: 7)
        #expect(query(defaultWindow) == ["channel_profile_id": "7"])
    }

    // MARK: - Support detection

    @Test("The probe asks for a window that ends before it starts")
    func probeIsInvalidWindow() throws {
        let items = query(DispatcharrGridWindow.probeURL(baseURL: base))
        let start = try Date(#require(items["start"]), strategy: .iso8601)
        let end = try Date(#require(items["end"]), strategy: .iso8601)
        #expect(end < start)
    }

    @Test("A rejected probe means windows are supported")
    func rejectedProbe() {
        #expect(DispatcharrGridWindow.supportsWindows(probeStatus: 400) == true)
    }

    @Test("A probe answered with a grid means the server ignored the window")
    func ignoredProbe() {
        #expect(DispatcharrGridWindow.supportsWindows(probeStatus: 200) == false)
    }

    @Test("Other statuses settle nothing", arguments: [401, 403, 404, 429, 500, 502, 503])
    func inconclusiveProbe(status: Int) {
        #expect(DispatcharrGridWindow.supportsWindows(probeStatus: status) == nil)
    }

    // MARK: - Window check

    @Test("Programs overlapping the window pass, including ones that straddle its edges")
    func overlappingProgramsRespectWindow() throws {
        let programs = [
            try program(id: "1", start: "2026-02-13T23:30:00Z", end: "2026-02-14T00:30:00Z"),
            try program(id: "2", start: "2026-02-14T12:00:00Z", end: "2026-02-14T13:00:00Z"),
            try program(id: "3", start: "2026-02-14T23:30:00Z", end: "2026-02-15T01:00:00Z")
        ]
        #expect(DispatcharrGridWindow.respectsWindow(programs, window: window))
        #expect(DispatcharrGridWindow.respectsWindow([], window: window))
    }

    @Test("A program outside the window gives away a server that ignored it")
    func strayProgramBreaksWindow() throws {
        let after = [
            try program(id: "1", start: "2026-02-14T12:00:00Z", end: "2026-02-14T13:00:00Z"),
            try program(id: "2", start: "2026-02-15T00:00:00Z", end: "2026-02-15T01:00:00Z")
        ]
        #expect(!DispatcharrGridWindow.respectsWindow(after, window: window))

        let before = [try program(id: "3", start: "2026-02-13T22:00:00Z", end: "2026-02-14T00:00:00Z")]
        #expect(!DispatcharrGridWindow.respectsWindow(before, window: window))
    }

    @Test("Generated placeholder programmes are not held to the window")
    func placeholdersAreNotJudged() throws {
        let placeholder = try program(
            id: #""dummy-standard-12-20260216T000000""#,
            start: "2026-02-16T00:00:00+00:00",
            end: "2026-02-16T04:00:00+00:00"
        )
        #expect(placeholder.idWasSynthetic)
        #expect(DispatcharrGridWindow.respectsWindow([placeholder], window: window))
    }

    // MARK: - Grid rows

    @Test("A placeholder row maps onto its channel through the channel UUID")
    func placeholderMapsByUUID() throws {
        let json = """
        {"id":"dummy-standard-12-20260214T000000","start_time":"2026-02-14T00:00:00+00:00",
         "end_time":"2026-02-14T04:00:00+00:00","title":"Channel 12","description":"",
         "tvg_id":"uuid-12","sub_title":null,"custom_properties":null,"season":null,"episode":null,
         "is_new":false,"is_live":false,"is_premiere":false,"is_finale":false}
        """
        let row = try JSONDecoder().decode(DispatcharrProgram.self, from: Data(json.utf8))
        let mapped = DispatcharrEPGProgramMapper.map(
            programs: [row],
            tvgIdToChannelIds: ["uuid-12": [12]],
            epgDataIdToChannelIds: [:],
            sortByStart: true
        )
        #expect(mapped[12]?.count == 1)
        #expect(mapped[12]?.first?.start == 1_771_027_200)
        #expect(mapped[12]?.first?.end == 1_771_027_200 + 4 * 3600)
    }

    @Test("The same placeholder id decodes to the same program id, so chunks dedupe")
    func placeholderIdIsStableInSession() throws {
        let id = #""dummy-custom-3-20260214T200000""#
        let first = try program(id: id, start: "2026-02-14T20:00:00Z", end: "2026-02-14T22:00:00Z")
        let second = try program(id: id, start: "2026-02-14T20:00:00Z", end: "2026-02-14T22:00:00Z")
        #expect(first.id == second.id)
    }
}
