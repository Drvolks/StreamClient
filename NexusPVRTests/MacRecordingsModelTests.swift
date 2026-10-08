//
//  MacRecordingsModelTests.swift
//  NexusPVRTests
//
//  Watch state and series grouping behind the macOS recordings list
//  (Midnight redesign).
//

import Foundation
import Testing
@testable import NextPVR

struct MacRecordingsModelTests {

    // MARK: - RecordingWatchState

    @Test("Never played is New")
    func neverPlayedIsNew() {
        #expect(RecordingWatchState(Recording(id: 1, name: "A", duration: 3600)) == .new)
        // A few seconds from an accidental play don't count.
        #expect(RecordingWatchState(Recording(id: 2, name: "A", duration: 3600, playbackPosition: 8)) == .new)
    }

    @Test("Part-watched is Resume, with the fraction played")
    func partWatchedIsResume() {
        let state = RecordingWatchState(Recording(id: 1, name: "A", duration: 3600, playbackPosition: 900))
        #expect(state == .resume(progress: 0.25))
        #expect(state.label == "Resume")
    }

    @Test("90% or more is Watched")
    func nearlyFinishedIsWatched() {
        #expect(RecordingWatchState(Recording(id: 1, name: "A", duration: 3600, playbackPosition: 3300)) == .watched)
    }

    // MARK: - RecordingSection.grouped

    @Test("Series come first in name order, one-off recordings last")
    func groupsSeriesThenSingles() {
        let recordings = [
            Recording(id: 1, name: "Zulu Show", season: 1, episode: 2),
            Recording(id: 2, name: "A Film"),
            Recording(id: 3, name: "alpha series", season: 2, episode: 1),
            Recording(id: 4, name: "Zulu Show", season: 1, episode: 1),
            Recording(id: 5, name: "Another Film")
        ]

        let sections = RecordingSection.grouped(recordings)

        #expect(sections.map(\.title) == ["alpha series", "Zulu Show", RecordingSection.singlesTitle])
        #expect(sections.map(\.isSeries) == [true, true, false])
        // Each section keeps the incoming order.
        #expect(sections[1].recordings.map(\.id) == [1, 4])
        #expect(sections[2].recordings.map(\.id) == [2, 5])
    }

    @Test("No single recordings means no singles section")
    func noSinglesSection() {
        let sections = RecordingSection.grouped([Recording(id: 1, name: "Show", season: 1, episode: 1)])
        #expect(sections.count == 1)
        #expect(sections[0].isSeries)
        #expect(RecordingSection.grouped([]).isEmpty)
    }

    @Test("A section adds up its recordings' sizes, skipping unknown ones")
    func totalBytes() {
        let section = RecordingSection.grouped([
            Recording(id: 1, name: "A", size: 1_000),
            Recording(id: 2, name: "B"),
            Recording(id: 3, name: "C", size: 500)
        ])[0]
        #expect(section.totalBytes == 1_500)
    }

    // MARK: - TopicMatcher on recordings

    @Test("Recordings match topics on their name, subtitle or description")
    func recordingTopicMatch() {
        #expect(TopicMatcher.matchedKeyword(name: "Evening", subtitle: nil, desc: "Biathlon World Cup", in: ["biathlon"]) == "biathlon")
        #expect(TopicMatcher.matchedKeyword(name: "Evening", subtitle: nil, desc: nil, in: ["golf"]) == nil)
    }

    // MARK: - Recording.episodeTitle

    @Test("The episode title is the subtitle without its SxxExx pattern")
    func episodeTitle() {
        #expect(Recording(id: 1, name: "NOVA", subtitle: "Space Wars").episodeTitle == "Space Wars")
        #expect(Recording(id: 2, name: "NOVA", subtitle: "S53E12 Space Wars").episodeTitle == "Space Wars")
        #expect(Recording(id: 3, name: "NOVA", subtitle: "  ").episodeTitle == nil)
        #expect(Recording(id: 4, name: "NOVA").episodeTitle == nil)
    }
}
