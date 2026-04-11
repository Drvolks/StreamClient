//
//  TopicProgramRowViewModelTests.swift
//  NexusPVRTests
//
//  Tests for the file-scope `normalizeProgramName` helper used to match
//  "already-recorded" candidates for an upcoming program.
//

import Testing
@testable import NextPVR

struct TopicProgramRowViewModelTests {

    @Test("Removes the Unicode superscript New marker from a program name")
    func removesNewMarker() {
        let out = TopicProgramRowViewModel.normalizeProgramName("Sample Show \u{1D3A}\u{1D49}\u{02B7}")
        #expect(out == "sample show")
    }

    @Test("Lowercases everything")
    func lowercases() {
        #expect(TopicProgramRowViewModel.normalizeProgramName("Sample SHOW") == "sample show")
    }

    @Test("Collapses internal runs of spaces")
    func collapsesSpaces() {
        #expect(TopicProgramRowViewModel.normalizeProgramName("Hello    World") == "hello world")
    }

    @Test("Trims leading and trailing whitespace")
    func trimsEdges() {
        #expect(TopicProgramRowViewModel.normalizeProgramName("  spaced  ") == "spaced")
    }

    @Test("Returns empty string for whitespace-only input")
    func emptyOnWhitespace() {
        #expect(TopicProgramRowViewModel.normalizeProgramName("   ") == "")
    }

    @Test("Two names that only differ by the New marker match after normalization")
    func newMarkerVariants() {
        let a = TopicProgramRowViewModel.normalizeProgramName("My Show \u{1D3A}\u{1D49}\u{02B7}")
        let b = TopicProgramRowViewModel.normalizeProgramName("my show")
        #expect(a == b)
    }

    @Test("Already-normalized input is idempotent")
    func idempotent() {
        let input = "the same"
        #expect(TopicProgramRowViewModel.normalizeProgramName(input) == input)
        #expect(TopicProgramRowViewModel.normalizeProgramName(TopicProgramRowViewModel.normalizeProgramName(input)) == input)
    }

    // MARK: - MatchingProgram.id

    @Test("MatchingProgram.id combines program id and channel id")
    func matchingProgramId() {
        let program = Program(
            id: 42,
            name: "Show",
            subtitle: nil,
            desc: nil,
            start: 0,
            end: 100,
            genres: nil,
            channelId: 7
        )
        let channel = Channel(id: 7, name: "ABC", number: 1)
        let match = MatchingProgram(program: program, channel: channel, matchedKeyword: "news")
        #expect(match.id == "42-7")
        #expect(match.matchedKeyword == "news")
    }

    @Test("MatchingProgram.scheduledKeyword has expected label")
    func scheduledKeyword() {
        #expect(MatchingProgram.scheduledKeyword == "Scheduled")
    }
}
