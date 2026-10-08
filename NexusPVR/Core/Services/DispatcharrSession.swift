//
//  DispatcharrSession.swift
//  nextpvr-apple-client
//
//  A saved Dispatcharr sign-in: the JWT pair and the credentials it belongs
//  to. See DispatcharrSessionStore.
//

import Foundation

nonisolated struct DispatcharrSession: Codable, Equatable {
    var access: String
    var refresh: String?
    /// `DispatcharrSessionStore.credentialKey(for:)` of the config that
    /// signed in; a session is only reused for the same server and login.
    var credentialKey: String
}
