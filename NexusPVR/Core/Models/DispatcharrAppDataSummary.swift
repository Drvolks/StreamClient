//
//  DispatcharrAppDataSummary.swift
//  DispatcherPVR
//
//  Body of `GET /api/accounts/users/me/app-data/` (#199). Only `limits` is
//  read: its presence is what tells a server with the endpoint apart from an
//  older one, whose catch-all route answers the same path with the web app's
//  HTML page and a 200.
//

import Foundation

nonisolated struct DispatcharrAppDataSummary: Decodable, Sendable {
    let limits: DispatcharrAppDataLimits
}
