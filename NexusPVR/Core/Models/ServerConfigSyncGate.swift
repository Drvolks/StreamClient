//
//  ServerConfigSyncGate.swift
//  nextpvr-apple-client
//
//  Suppresses iCloud server-config sync while the user is editing it
//

import Foundation

/// Guards the iCloud `ServerConfig` sync observer while the server setup sheet
/// is open. Without it, a config pushed from another device (or republished by
/// a device holding a stale copy) lands mid-edit and overwrites the address the
/// user just typed, along with the tokens from the connect it kicked off.
@MainActor
enum ServerConfigSyncGate {
    private static var holds = 0

    /// True while an edit is in progress and external syncs must be ignored.
    static var isSuspended: Bool { holds > 0 }

    static func acquire() {
        holds += 1
    }

    static func release() {
        holds = max(0, holds - 1)
    }
}
