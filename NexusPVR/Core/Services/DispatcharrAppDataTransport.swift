//
//  DispatcharrAppDataTransport.swift
//  DispatcherPVR
//
//  The authenticated requests `DispatcharrPositionSync` makes (#199).
//  `DispatcherClient` provides them; tests use a fake server.
//

import Foundation

@MainActor
protocol DispatcharrAppDataTransport: AnyObject {
    /// False when there is no server to sync with (not configured, demo mode).
    var appDataSyncAllowed: Bool { get }
    /// Sends `method` to the app-data collection (`key` nil) or to one key,
    /// and returns the response whatever its status.
    func appDataResponse(key: String?, method: String, body: Data?) async throws -> (data: Data, status: Int)
}
