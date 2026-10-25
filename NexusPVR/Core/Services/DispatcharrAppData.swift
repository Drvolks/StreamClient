//
//  DispatcharrAppData.swift
//  DispatcherPVR
//
//  Request building and the stored format for Dispatcharr's per-user app
//  data, where the app keeps a copy of the playback positions (#199).
//

import Foundation

nonisolated enum DispatcharrAppData {
    /// Keys are namespaces, not secrets: any credential for the user can read
    /// them. One per store, so each stays well under the per-key limit.
    static let recordingPositionsKey = "com.drvolks.streamclient.recording-positions"
    static let vodProgressKey = "com.drvolks.streamclient.vod-progress"

    /// The collection when `key` is nil, one key otherwise.
    static func url(baseURL: String, key: String? = nil) -> URL? {
        let collection = "\(baseURL)/api/accounts/users/me/app-data/"
        guard let key else { return URL(string: collection) }
        guard let escaped = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "\(collection)\(escaped)/")
    }

    enum Support: Equatable, Sendable {
        case supported(maxValueBytes: Int)
        case unsupported
    }

    /// What the answer to `GET` on the collection says about the server, nil
    /// when it says nothing either way (a server error, say), so the question
    /// is asked again later.
    static func support(status: Int, data: Data) -> Support? {
        switch status {
        case 200:
            guard let summary = try? JSONDecoder().decode(DispatcharrAppDataSummary.self, from: data) else {
                // An older server's catch-all route serves the web app here.
                return .unsupported
            }
            return .supported(maxValueBytes: summary.limits.maxValueBytes)
        case 403, 404, 405:
            return .unsupported
        default:
            return nil
        }
    }

    static func errorCode(in data: Data) -> String? {
        (try? JSONDecoder().decode(DispatcharrAppDataErrorBody.self, from: data))?.code
    }

    // MARK: - Stored format

    /// The store's own JSON, with dates as whole milliseconds since 1970 and
    /// keys sorted, so an unchanged store encodes to the same bytes.
    static func encode<Store: Encodable>(_ store: Store) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.millisecondsSince1970)
        }
        return try? encoder.encode(store)
    }

    static func decode<Store: Decodable>(_ type: Store.Type, from data: Data) -> Store? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            return Date(millisecondsSince1970: try container.decode(Int64.self))
        }
        return try? decoder.decode(type, from: data)
    }

    /// `store` cut down to its newest entries until it encodes to at most
    /// `maxBytes`, and to `maxEntries` when given.
    static func fitted<Store: ServerSyncedPositionStore>(
        _ store: Store,
        maxBytes: Int,
        maxEntries: Int? = nil
    ) -> (store: Store, data: Data)? {
        var store = store
        if let maxEntries, store.entryCount > maxEntries {
            store.keepNewest(maxEntries)
        }
        while let data = encode(store) {
            if data.count <= maxBytes { return (store, data) }
            guard store.entryCount > 0 else { return nil }
            // Shrink in proportion to the overshoot, by at least one entry.
            let estimate = Int(Double(store.entryCount) * Double(maxBytes) / Double(data.count) * 0.95)
            store.keepNewest(min(estimate, store.entryCount - 1))
        }
        return nil
    }
}
