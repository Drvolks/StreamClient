//
//  LogShareStatus.swift
//  PVR Client
//
//  State of the Apple TV's temporary log page.
//

import Foundation

/// State of `LogShareServer`, the Apple TV's temporary log page.
nonisolated enum LogShareStatus: Equatable, Sendable {
    case starting
    /// Serving; open this URL from another device on the network.
    case ready(URL)
    case failed(String)
}
