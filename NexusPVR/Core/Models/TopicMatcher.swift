//
//  TopicMatcher.swift
//  nextpvr-apple-client
//
//  Which of the user's topic keywords a program matches.
//

import Foundation

nonisolated enum TopicMatcher {
    /// The first keyword found in the program's name, subtitle or
    /// description (case-insensitive), as the user typed it.
    static func matchedKeyword(for program: Program, in keywords: [String]) -> String? {
        guard !keywords.isEmpty else { return nil }
        let text = [program.name, program.subtitle ?? "", program.desc ?? ""]
            .joined(separator: " ")
            .lowercased()
        return keywords.first { !$0.isEmpty && text.contains($0.lowercased()) }
    }
}
