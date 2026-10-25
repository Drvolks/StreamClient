//
//  DispatcharrAppDataErrorBody.swift
//  DispatcherPVR
//
//  The `{detail, code}` body of an app-data error (#199).
//

import Foundation

nonisolated struct DispatcharrAppDataErrorBody: Decodable, Sendable {
    let detail: String?
    let code: String?

    /// A 404 with this code is a key that holds nothing yet; a 404 without it
    /// is a server that has no app-data route.
    static let keyNotFound = "key_not_found"
}
