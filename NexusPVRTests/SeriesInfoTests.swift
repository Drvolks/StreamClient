//
//  SeriesInfoTests.swift
//  NexusPVRTests
//
//  Tests for SeriesInfo pattern parsing.
//

import Testing
@testable import NextPVR

struct SeriesInfoTests {

    // MARK: - displayString

    @Test("displayString formats season and episode")
    func displayString() {
        let info = SeriesInfo(season: 3, episode: 7, seriesName: "Show")
        #expect(info.displayString == "Season 3 Episode 7")
    }

    @Test("shortDisplayString zero-pads to two digits")
    func shortDisplayString() {
        #expect(SeriesInfo(season: 1, episode: 2, seriesName: "X").shortDisplayString == "S01E02")
        #expect(SeriesInfo(season: 12, episode: 34, seriesName: "X").shortDisplayString == "S12E34")
    }

    // MARK: - stripPattern

    @Test("stripPattern removes SxxExx and trailing dash")
    func stripPattern_trailingSeparator() {
        #expect(SeriesInfo.stripPattern(from: "S01E05 - Episode Title") == "Episode Title")
    }

    @Test("stripPattern removes pattern from end of string")
    func stripPattern_atEnd() {
        #expect(SeriesInfo.stripPattern(from: "My Show S02E10") == "My Show")
    }

    @Test("stripPattern handles lowercase sxxexx")
    func stripPattern_lowercase() {
        #expect(SeriesInfo.stripPattern(from: "Show s03e04") == "Show")
    }

    @Test("stripPattern returns original when no pattern present")
    func stripPattern_noPattern() {
        #expect(SeriesInfo.stripPattern(from: "Plain Title") == "Plain Title")
    }

    @Test("stripPattern handles em dash, en dash, and colon separators")
    func stripPattern_variousSeparators() {
        #expect(SeriesInfo.stripPattern(from: "S01E01—Title") == "Title")
        #expect(SeriesInfo.stripPattern(from: "S01E01–Title") == "Title")
        #expect(SeriesInfo.stripPattern(from: "S01E01:Title") == "Title")
    }

    // MARK: - parse

    @Test("parse extracts season/episode from subtitle")
    func parse_subtitleFirst() {
        let info = SeriesInfo.parse(name: "Show", subtitle: "S02E05")
        #expect(info?.season == 2)
        #expect(info?.episode == 5)
    }

    @Test("parse uses subtitle when both subtitle and name contain pattern")
    func parse_subtitleBeforeName() {
        let info = SeriesInfo.parse(name: "Name S09E09", subtitle: "S02E05")
        #expect(info?.season == 2)
        #expect(info?.episode == 5)
    }

    @Test("parse falls back to name when subtitle missing")
    func parse_fromName() {
        let info = SeriesInfo.parse(name: "My Show S04E12")
        #expect(info?.season == 4)
        #expect(info?.episode == 12)
        #expect(info?.seriesName == "My Show")
    }

    @Test("parse falls back to description when neither name nor subtitle have it")
    func parse_fromDesc() {
        let info = SeriesInfo.parse(name: "Show", subtitle: "Plain", desc: "Recap of S05E10")
        #expect(info?.season == 5)
        #expect(info?.episode == 10)
    }

    @Test("parse returns nil when no pattern is found")
    func parse_nilWhenMissing() {
        #expect(SeriesInfo.parse(name: "Show", subtitle: "Plain", desc: "Nothing") == nil)
    }

    @Test("parse strips pattern from seriesName")
    func parse_stripsFromName() {
        let info = SeriesInfo.parse(name: "The Show S01E02")
        #expect(info?.seriesName == "The Show")
    }
}
