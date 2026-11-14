//
//  LogShareRequest.swift
//  PVR Client
//
//  Text to share from the Event Log, and what to call it.
//

import Foundation

/// A log about to be shared: the whole Event Log or one playback session.
nonisolated struct LogShareRequest: Identifiable, Sendable {
    let id = UUID()
    /// "Event Log" or "Playback Session", shown on the share screen.
    let title: String
    let fileName: String
    let text: String
}
