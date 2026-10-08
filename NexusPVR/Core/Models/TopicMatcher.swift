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
        matchedKeyword(name: program.name, subtitle: program.subtitle, desc: program.desc, in: keywords)
    }

    /// Same rule for anything with a name, subtitle and description, such as a
    /// recording.
    static func matchedKeyword(name: String, subtitle: String?, desc: String?, in keywords: [String]) -> String? {
        guard !keywords.isEmpty else { return nil }
        let text = [name, subtitle ?? "", desc ?? ""]
            .joined(separator: " ")
            .lowercased()
        return keywords.first { !$0.isEmpty && text.contains($0.lowercased()) }
    }
}
