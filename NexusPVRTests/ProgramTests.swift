//
//  ProgramTests.swift
//  NexusPVRTests
//
//  Tests for Program computed properties and helpers.
//

import Testing
import Foundation
@testable import NextPVR

struct ProgramTests {

    private func program(
        start: Int,
        end: Int,
        name: String = "Test",
        subtitle: String? = nil,
        desc: String? = nil,
        season: Int? = nil,
        episode: Int? = nil
    ) -> Program {
        Program(
            id: 1,
            name: name,
            subtitle: subtitle,
            desc: desc,
            start: start,
            end: end,
            genres: nil,
            channelId: 1,
            season: season,
            episode: episode
        )
    }

    // MARK: - Duration

    @Test("duration is end - start in seconds")
    func duration() {
        let p = program(start: 1000, end: 4600)
        #expect(p.duration == 3600)
    }

    @Test("durationMinutes converts to whole minutes")
    func durationMinutes() {
        let p = program(start: 0, end: 5400) // 90 minutes
        #expect(p.durationMinutes == 90)
    }

    // MARK: - progress(at:)
    //
    // Note: `Program.progress(at:)` short-circuits via `isCurrentlyAiring`, which
    // consults the real system clock. To test the actual elapsed/duration math,
    // the program's window must include "now". We anchor start/end around Date()
    // and inject the `at` argument for the arithmetic branch.

    @Test("progress is past a quarter at ~25% through an airing window")
    func progress_quarterwayWhileAiring() {
        let now = Date()
        let start = now.addingTimeInterval(-250)
        let end = now.addingTimeInterval(750)
        let p = program(
            start: Int(start.timeIntervalSince1970),
            end: Int(end.timeIntervalSince1970)
        )
        let progress = p.progress(at: start.addingTimeInterval(250))
        // Allow a small tolerance: rounding to Int timestamps loses sub-second
        // precision, so progress lands near but not exactly on 0.25.
        #expect(abs(progress - 0.25) < 0.01)
    }

    @Test("progress is clamped to 1.0 when passed a date past program end")
    func progress_clampedAfterEnd() {
        let now = Date()
        let start = now.addingTimeInterval(-100)
        let end = now.addingTimeInterval(100)
        let p = program(
            start: Int(start.timeIntervalSince1970),
            end: Int(end.timeIntervalSince1970)
        )
        #expect(p.progress(at: end.addingTimeInterval(10_000)) == 1.0)
    }

    @Test("progress is 1 for programs that ended in the past")
    func progress_endedProgramReturnsOne() {
        let now = Int(Date().timeIntervalSince1970)
        let p = program(start: now - 3600, end: now - 1800)
        #expect(p.progress() == 1.0)
    }

    @Test("progress is 0 for programs that haven't started")
    func progress_futureProgramReturnsZero() {
        let now = Int(Date().timeIntervalSince1970)
        let p = program(start: now + 1800, end: now + 3600)
        #expect(p.progress() == 0.0)
    }

    // MARK: - isCurrentlyAiring

    @Test("program airing at start is currently airing")
    func airing_atStart() {
        let now = Date()
        let p = program(
            start: Int(now.timeIntervalSince1970) - 100,
            end: Int(now.timeIntervalSince1970) + 100
        )
        #expect(p.isCurrentlyAiring)
    }

    @Test("program entirely in the past is not airing")
    func airing_past() {
        let now = Int(Date().timeIntervalSince1970)
        let p = program(start: now - 3600, end: now - 1800)
        #expect(p.isCurrentlyAiring == false)
        #expect(p.hasEnded)
    }

    @Test("program entirely in the future is not airing")
    func airing_future() {
        let now = Int(Date().timeIntervalSince1970)
        let p = program(start: now + 1800, end: now + 3600)
        #expect(p.isCurrentlyAiring == false)
        #expect(p.hasEnded == false)
    }

    // MARK: - isNew / cleanName

    @Test("isNew detects the unicode New marker")
    func isNew_positive() {
        let p = program(start: 0, end: 100, name: "Sample Show \u{1D3A}\u{1D49}\u{02B7}")
        #expect(p.isNew)
    }

    @Test("isNew is false for normal names")
    func isNew_negative() {
        let p = program(start: 0, end: 100, name: "Sample Show")
        #expect(p.isNew == false)
    }

    @Test("cleanName strips the New marker and surrounding whitespace")
    func cleanName_stripsMarker() {
        let p = program(start: 0, end: 100, name: "Sample Show \u{1D3A}\u{1D49}\u{02B7}")
        #expect(p.cleanName == "Sample Show")
    }

    @Test("cleanName is unchanged for normal names")
    func cleanName_unchanged() {
        let p = program(start: 0, end: 100, name: "Sample Show")
        #expect(p.cleanName == "Sample Show")
    }

    // MARK: - seriesInfo

    @Test("seriesInfo uses explicit season/episode fields when positive")
    func seriesInfo_explicit() {
        let p = program(start: 0, end: 100, name: "Show", season: 3, episode: 7)
        let info = p.seriesInfo
        #expect(info?.season == 3)
        #expect(info?.episode == 7)
        #expect(info?.seriesName == "Show")
    }

    @Test("seriesInfo falls back to parsing the name when season/episode missing")
    func seriesInfo_parsedFromName() {
        let p = program(start: 0, end: 100, name: "Sample Show S02E05")
        let info = p.seriesInfo
        #expect(info?.season == 2)
        #expect(info?.episode == 5)
    }

    @Test("seriesInfo returns nil when no pattern is found")
    func seriesInfo_missing() {
        let p = program(start: 0, end: 100, name: "Random Show")
        #expect(p.seriesInfo == nil)
    }

    // MARK: - Codable

    @Test("Program decodes with event_id/title/start_time aliases")
    func codable_decodesAliases() throws {
        let json = """
        {
            "event_id": 42,
            "title": "Sample",
            "start_time": 1000,
            "end_time": 2000
        }
        """
        let p = try JSONDecoder().decode(Program.self, from: Data(json.utf8))
        #expect(p.id == 42)
        #expect(p.name == "Sample")
        #expect(p.start == 1000)
        #expect(p.end == 2000)
    }

    @Test("Program.preview returns a plausible one-hour fixture")
    func previewFixture() {
        let p = Program.preview
        #expect(p.name == "Sample Show")
        #expect(p.duration == 3600)
        #expect(p.channelId == 1)
        #expect(p.subtitle == "Episode Title")
        #expect((p.genres ?? []).contains("Drama"))
    }

    @Test("Program decodes with canonical key names")
    func codable_decodesCanonical() throws {
        let json = """
        {
            "id": 7,
            "name": "Canonical",
            "start": 100,
            "end": 200
        }
        """
        let p = try JSONDecoder().decode(Program.self, from: Data(json.utf8))
        #expect(p.id == 7)
        #expect(p.name == "Canonical")
    }
    // MARK: - Dispatcharr EPG mapping

    @Test("Dispatcharr programs decode epg_data_id as int or string")
    func dispatcharrProgram_decodesEPGDataId() throws {
        let intJSON = """
        {"id":1,"start_time":"2026-01-01T00:00:00Z","end_time":"2026-01-01T01:00:00Z","title":"Program","epg_data_id":42}
        """
        let stringJSON = """
        {"id":2,"start_time":"2026-01-01T00:00:00Z","end_time":"2026-01-01T01:00:00Z","title":"Program","epg_data_id":"43"}
        """

        let intProgram = try JSONDecoder().decode(DispatcharrProgram.self, from: Data(intJSON.utf8))
        let stringProgram = try JSONDecoder().decode(DispatcharrProgram.self, from: Data(stringJSON.utf8))

        #expect(intProgram.epgDataId == 42)
        #expect(stringProgram.epgDataId == 43)
    }

    @Test("Dispatcharr EPG mapper fans dummy epg_data_id programs out to all channels")
    func dispatcharrMapper_mapsSharedDummyEPGDataIdToAllChannels() throws {
        let programs = try decodeDispatcharrPrograms("""
        [
            {"id":10,"start_time":"2026-01-01T00:00:00Z","end_time":"2026-01-01T01:00:00Z","title":"Live Event","epg_data_id":9001}
        ]
        """)

        let mapped = DispatcharrEPGProgramMapper.map(
            programs: programs,
            tvgIdToChannelIds: [:],
            epgDataIdToChannelIds: [9001: [101, 102]],
            sortByStart: true
        )

        #expect(mapped[101]?.map(\.name) == ["Live Event"])
        #expect(mapped[102]?.map(\.name) == ["Live Event"])
        #expect(mapped[101]?.first?.channelId == 101)
        #expect(mapped[102]?.first?.channelId == 102)
    }

    @Test("Dispatcharr EPG mapper fans shared tvg_id programs out to all channels")
    func dispatcharrMapper_mapsSharedTVGIdToAllChannels() throws {
        let programs = try decodeDispatcharrPrograms("""
        [
            {"id":11,"start_time":"2026-01-01T00:00:00Z","end_time":"2026-01-01T01:00:00Z","title":"Shared TVG Event","tvg_id":"dummy-live"}
        ]
        """)

        let mapped = DispatcharrEPGProgramMapper.map(
            programs: programs,
            tvgIdToChannelIds: ["dummy-live": [201, 202]],
            epgDataIdToChannelIds: [:],
            sortByStart: true
        )

        #expect(mapped[201]?.map(\.name) == ["Shared TVG Event"])
        #expect(mapped[202]?.map(\.name) == ["Shared TVG Event"])
    }

    @Test("Dispatcharr EPG mapper resolves dummy grid programs by channel UUID tvg_id")
    func dispatcharrMapper_mapsChannelUUIDTVGId() throws {
        let channelUUID = "5214c69b-97e4-4b79-ade1-18b8a5d4923e"
        let programs = try decodeDispatcharrPrograms("""
        [
            {"id":"dummy-custom-596-17","start_time":"2026-06-18T17:00:00+00:00","end_time":"2026-06-18T20:00:00+00:00","title":" Velenje – Rogaska Slatina  - {date} {starttime24}","tvg_id":"\(channelUUID)"}
        ]
        """)

        let mapped = DispatcharrEPGProgramMapper.map(
            programs: programs,
            tvgIdToChannelIds: [channelUUID: [596]],
            epgDataIdToChannelIds: [:],
            sortByStart: true
        )

        #expect(mapped[596]?.map(\.name) == [" Velenje – Rogaska Slatina  - {date} {starttime24}"])
        #expect(mapped[596]?.first?.channelId == 596)
    }

    @Test("Dispatcharr EPG mapper prefers epg_data_id over colliding tvg_id")
    func dispatcharrMapper_prefersEPGDataIdOverTVGId() throws {
        let programs = try decodeDispatcharrPrograms("""
        [
            {"id":12,"start_time":"2026-01-01T00:00:00Z","end_time":"2026-01-01T01:00:00Z","title":"Dummy Event","tvg_id":"shared","epg_data_id":77}
        ]
        """)

        let mapped = DispatcharrEPGProgramMapper.map(
            programs: programs,
            tvgIdToChannelIds: ["shared": [301]],
            epgDataIdToChannelIds: [77: [302, 303]],
            sortByStart: true
        )

        #expect(mapped[301] == nil)
        #expect(mapped[302]?.map(\.name) == ["Dummy Event"])
        #expect(mapped[303]?.map(\.name) == ["Dummy Event"])
    }

    private func decodeDispatcharrPrograms(_ json: String) throws -> [DispatcharrProgram] {
        try JSONDecoder().decode([DispatcharrProgram].self, from: Data(json.utf8))
    }
}
