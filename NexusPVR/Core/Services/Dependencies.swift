//
//  Dependencies.swift
//  PVR Client
//
//  Central default dependency provider for app-wide singleton access.
//  All app-wide services should be accessed through Dependencies.default
//  to enable dependency injection and testability.
//

import Foundation

/// Provides default app-wide service instances.
/// Individual types accept explicit dependencies for callers that need non-default instances.
enum Dependencies {
    private static let defaultImageCache = ImageCache()

    private static let defaultNetworkEventLog = NetworkEventLog()

    @MainActor
    private static let defaultActivePlayerSession = ActivePlayerSession()

    /// App-wide default image cache (thread-safe NSCache-backed)
    static var imageCache: any ImageCaching {
        defaultImageCache
    }

    /// App-wide default network event logger (protocol for testability)
    static var networkEventLogger: any NetworkEventLogging {
        defaultNetworkEventLog
    }

    /// App-wide default concrete network event log (for @ObservedObject injection)
    @MainActor
    static var networkEventLog: NetworkEventLog {
        defaultNetworkEventLog
    }

    /// App-wide default active player session manager
    @MainActor
    static var activePlayerSession: any ActivePlayerSessionManaging {
        defaultActivePlayerSession
    }

    /// App-wide default concrete active player session (for direct access)
    @MainActor
    static var playerSession: ActivePlayerSession {
        defaultActivePlayerSession
    }
}
