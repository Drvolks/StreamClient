//
//  DispatcharrAppDataTests.swift
//  NexusPVRTests
//
//  Dispatcharr app-data requests and the stored position format (#199).
//

import Testing
import Foundation
@testable import NextPVR

struct DispatcharrAppDataTests {

    @Test("URLs for the collection and for one key")
    func urls() {
        #expect(DispatcharrAppData.url(baseURL: "http://tv:9191")?.absoluteString
                == "http://tv:9191/api/accounts/users/me/app-data/")
        #expect(DispatcharrAppData.url(baseURL: "http://tv:9191", key: DispatcharrAppData.vodProgressKey)?.absoluteString
                == "http://tv:9191/api/accounts/users/me/app-data/com.drvolks.streamclient.vod-progress/")
    }

    @Test("Keys follow the server's rules: 8 to 64 characters of [A-Za-z0-9._-], starting with a letter or digit")
    func keysAreValid() throws {
        let rule = try Regex("^[A-Za-z0-9][A-Za-z0-9._-]{7,63}$")
        for key in [DispatcharrAppData.recordingPositionsKey, DispatcharrAppData.vodProgressKey] {
            #expect(key.wholeMatch(of: rule) != nil, "\(key)")
        }
    }

    @Test("The collection's answer tells a current server from an older one")
    func support() {
        let summary = Data(#"{"limits":{"max_value_bytes":131072,"max_total_bytes":1048576,"max_apps":25},"total_bytes":0,"apps":[]}"#.utf8)
        #expect(DispatcharrAppData.support(status: 200, data: summary) == .supported(maxValueBytes: 131072))
        // An older server's catch-all route answers with the web app.
        #expect(DispatcharrAppData.support(status: 200, data: Data("<!doctype html>".utf8)) == .unsupported)
        #expect(DispatcharrAppData.support(status: 404, data: Data()) == .unsupported)
        #expect(DispatcharrAppData.support(status: 500, data: Data()) == nil)
    }

    @Test("Error bodies give their code")
    func errorCode() {
        #expect(DispatcharrAppData.errorCode(in: Data(#"{"detail":"x","code":"key_not_found"}"#.utf8)) == "key_not_found")
        #expect(DispatcharrAppData.errorCode(in: Data("nope".utf8)) == nil)
    }

    @Test("Dates are stored as whole milliseconds since 1970 and come back equal")
    func roundTrip() throws {
        var store = RecordingPositionStore()
        store.set(recordingId: 7, position: 600, at: Date(timeIntervalSince1970: 1_761_400_000.123_456))
        let data = try #require(DispatcharrAppData.encode(store))

        #expect(String(decoding: data, as: UTF8.self)
                == #"{"entries":{"7":{"position":600,"updatedAt":1761400000123}}}"#)
        #expect(DispatcharrAppData.decode(RecordingPositionStore.self, from: data) == store)
    }

    @Test("VOD progress round-trips too")
    func vodRoundTrip() throws {
        var store = VODProgressStore()
        store.record(uuid: "0b6a0e5e-1111-2222-3333-444455556666", position: 300, duration: 5400,
                     at: Date(timeIntervalSince1970: 1_761_400_000.5))
        let data = try #require(DispatcharrAppData.encode(store))
        #expect(DispatcharrAppData.decode(VODProgressStore.self, from: data) == store)
    }

    @Test("A full store of each kind fits the server's default 128 KiB per key")
    func fullStoresFit() throws {
        var recordings = RecordingPositionStore()
        var vod = VODProgressStore()
        let now = Date()
        for index in 0..<500 {
            let at = now.addingTimeInterval(TimeInterval(index))
            recordings.set(recordingId: 100_000 + index, position: 12_345, at: at)
            vod.record(uuid: UUID().uuidString.lowercased(), position: 12_345, duration: 54_321, at: at)
        }
        let recordingBytes = try #require(DispatcharrAppData.encode(recordings)).count
        let vodBytes = try #require(DispatcharrAppData.encode(vod)).count
        #expect(recordingBytes < 128 * 1024)
        #expect(vodBytes < 128 * 1024)
    }

    @Test("Fitting keeps the newest entries under the byte limit")
    func fitting() throws {
        var store = RecordingPositionStore()
        for id in 1...100 {
            store.set(recordingId: id, position: 100, at: Date(timeIntervalSince1970: TimeInterval(id)))
        }
        let fit = try #require(DispatcharrAppData.fitted(store, maxBytes: 1_000))
        #expect(fit.data.count <= 1_000)
        #expect(fit.store[100] != nil)
        #expect(fit.store[1] == nil)

        let capped = try #require(DispatcharrAppData.fitted(store, maxBytes: 100_000, maxEntries: 10))
        #expect(capped.store.entryCount == 10)
    }
}
