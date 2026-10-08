//
//  TopicMatcherTests.swift
//  NexusPVRTests
//

import Foundation
import Testing
@testable import NextPVR

struct TopicMatcherTests {
    private func program(name: String, subtitle: String? = nil, desc: String? = nil) -> Program {
        Program(id: 1, name: name, subtitle: subtitle, desc: desc, start: 0, end: 3600, genres: nil, channelId: 1)
    }

    @Test("Matches the name, subtitle or description, ignoring case")
    func matchesEveryField() {
        #expect(TopicMatcher.matchedKeyword(for: program(name: "Tour de France"), in: ["france"]) == "france")
        #expect(TopicMatcher.matchedKeyword(for: program(name: "News", subtitle: "Cycling round-up"), in: ["Cycling"]) == "Cycling")
        #expect(TopicMatcher.matchedKeyword(for: program(name: "Live", desc: "Stage 5 of the TOUR"), in: ["tour"]) == "tour")
    }

    @Test("Returns the first keyword that matches, as the user typed it")
    func firstMatchWins() {
        let p = program(name: "Tennis and Cycling")
        #expect(TopicMatcher.matchedKeyword(for: p, in: ["Cycling", "Tennis"]) == "Cycling")
    }

    @Test("No keywords, empty keywords or no match return nil")
    func noMatch() {
        let p = program(name: "Evening News")
        #expect(TopicMatcher.matchedKeyword(for: p, in: []) == nil)
        #expect(TopicMatcher.matchedKeyword(for: p, in: [""]) == nil)
        #expect(TopicMatcher.matchedKeyword(for: p, in: ["golf"]) == nil)
    }
}
