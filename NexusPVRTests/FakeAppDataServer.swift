//
//  FakeAppDataServer.swift
//  NexusPVRTests
//
//  An in-memory Dispatcharr app-data endpoint for `DispatcharrPositionSync`
//  tests (#199), plus an in-memory copy of the local stores.
//

import Foundation
@testable import NextPVR

@MainActor
final class FakeAppDataServer: DispatcharrAppDataTransport {
    enum Kind {
        /// Has the endpoint, with this per-key limit.
        case current(maxValueBytes: Int)
        /// Predates it: the catch-all route serves the web app.
        case legacy
    }

    var kind: Kind
    var appDataSyncAllowed = true
    private(set) var values: [String: Data] = [:]
    private(set) var requests: [(method: String, key: String?)] = []
    /// Statuses the next PUTs answer with instead of storing, in order.
    var forcedPutStatuses: [(status: Int, code: String)] = []

    init(kind: Kind = .current(maxValueBytes: 128 * 1024)) {
        self.kind = kind
    }

    var puts: Int { requests.filter { $0.method == "PUT" }.count }

    func store(_ data: Data, for key: String) {
        values[key] = data
    }

    func appDataResponse(key: String?, method: String, body: Data?) async throws -> (data: Data, status: Int) {
        requests.append((method, key))
        guard case .current(let maxValueBytes) = kind else {
            return (Data("<!doctype html><html></html>".utf8), 200)
        }
        guard let key else {
            let summary = #"{"limits":{"max_value_bytes":\#(maxValueBytes),"max_total_bytes":1048576,"max_apps":25},"total_bytes":0,"apps":[]}"#
            return (Data(summary.utf8), 200)
        }
        switch method {
        case "GET":
            guard let value = values[key] else {
                return (Data(#"{"detail":"App data not found for this key.","code":"key_not_found"}"#.utf8), 404)
            }
            return (value, 200)
        case "PUT":
            if !forcedPutStatuses.isEmpty {
                let forced = forcedPutStatuses.removeFirst()
                return (Data(#"{"detail":"refused","code":"\#(forced.code)"}"#.utf8), forced.status)
            }
            guard let body else { return (Data(), 400) }
            if body.count > maxValueBytes {
                return (Data(#"{"detail":"too large","code":"value_too_large"}"#.utf8), 413)
            }
            values[key] = body
            return (body, 200)
        default:
            return (Data(), 405)
        }
    }
}

/// This device's copy of the stores, without UserDefaults or iCloud.
@MainActor
final class InMemoryPositionStorage {
    var recordings = RecordingPositionStore()
    var vod = VODProgressStore()
    private(set) var recordingSaves = 0
    private(set) var vodSaves = 0

    var storage: DispatcharrPositionSyncStorage {
        DispatcharrPositionSyncStorage(
            loadRecordings: { self.recordings },
            saveRecordings: { self.recordings = $0; self.recordingSaves += 1 },
            loadVOD: { self.vod },
            saveVOD: { self.vod = $0; self.vodSaves += 1 }
        )
    }
}
