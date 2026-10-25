//
//  DispatcharrPositionSyncTests.swift
//  NexusPVRTests
//
//  Playback positions kept in Dispatcharr's per-user app data (#199):
//  detecting the endpoint, merging the server copy in, writing the merged
//  result back, and staying within the server's limits.
//

import Testing
import Foundation
@testable import NextPVR

@MainActor
struct DispatcharrPositionSyncTests {

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + seconds)
    }

    private func makeSync(_ server: FakeAppDataServer, _ local: InMemoryPositionStorage) -> DispatcharrPositionSync {
        DispatcharrPositionSync(
            transport: server,
            storage: local.storage,
            notificationCenter: NotificationCenter(),
            debounce: .milliseconds(10)
        )
    }

    private func serverRecordings(_ server: FakeAppDataServer) -> RecordingPositionStore? {
        server.values[DispatcharrAppData.recordingPositionsKey]
            .flatMap { DispatcharrAppData.decode(RecordingPositionStore.self, from: $0) }
    }

    // MARK: - Detecting the endpoint

    @Test("An older server's web page means no server sync, and nothing is written")
    func legacyServer() async {
        let server = FakeAppDataServer(kind: .legacy)
        let local = InMemoryPositionStorage()
        local.recordings.set(recordingId: 1, position: 600, at: date(0))
        let sync = makeSync(server, local)

        await sync.syncNow()
        await sync.syncNow()

        #expect(sync.support == .unsupported)
        #expect(server.requests.count == 1, "probed once, then left alone")
        #expect(server.puts == 0)
    }

    @Test("Nothing is sent when sync isn't allowed (demo mode, no server)")
    func notAllowed() async {
        let server = FakeAppDataServer()
        server.appDataSyncAllowed = false
        let local = InMemoryPositionStorage()
        local.recordings.set(recordingId: 1, position: 600, at: date(0))

        await makeSync(server, local).syncNow()

        #expect(server.requests.isEmpty)
    }

    // MARK: - Merging

    @Test("The first sync uploads this device's positions")
    func firstUpload() async {
        let server = FakeAppDataServer()
        let local = InMemoryPositionStorage()
        local.recordings.set(recordingId: 1, position: 600, at: date(0))
        local.vod.record(uuid: "abc", position: 300, duration: 5400, at: date(0))

        await makeSync(server, local).syncNow()

        #expect(serverRecordings(server) == local.recordings)
        #expect(server.values[DispatcharrAppData.vodProgressKey].flatMap {
            DispatcharrAppData.decode(VODProgressStore.self, from: $0)
        } == local.vod)
        #expect(local.recordingSaves == 0, "nothing new arrived")
    }

    @Test("Newer positions from the server replace older local ones, and the merge goes back up")
    func mergeBothWays() async throws {
        var remote = RecordingPositionStore()
        remote.set(recordingId: 1, position: 900, at: date(100))   // newer than local
        remote.set(recordingId: 2, position: 50, at: date(0))      // older than local
        let server = FakeAppDataServer()
        server.store(try #require(DispatcharrAppData.encode(remote)), for: DispatcharrAppData.recordingPositionsKey)

        let local = InMemoryPositionStorage()
        local.recordings.set(recordingId: 1, position: 600, at: date(0))
        local.recordings.set(recordingId: 2, position: 1200, at: date(100))
        local.recordings.set(recordingId: 3, position: 30, at: date(50))
        await makeSync(server, local).syncNow()

        #expect(local.recordings[1]?.position == 900)
        #expect(local.recordings[2]?.position == 1200)
        #expect(local.recordings[3]?.position == 30)
        #expect(local.recordingSaves == 1)
        #expect(serverRecordings(server) == local.recordings)
    }

    @Test("A reset on another user's device wins over an older local position")
    func resetFromServer() async throws {
        var remote = RecordingPositionStore()
        remote.set(recordingId: 1, position: 0, at: date(100))
        let server = FakeAppDataServer()
        server.store(try #require(DispatcharrAppData.encode(remote)), for: DispatcharrAppData.recordingPositionsKey)
        let local = InMemoryPositionStorage()
        local.recordings.set(recordingId: 1, position: 600, at: date(0))

        await makeSync(server, local).syncNow()

        #expect(local.recordings.resumePosition(for: 1) == nil)
    }

    @Test("When both copies already agree, nothing is written")
    func noRedundantWrites() async {
        let server = FakeAppDataServer()
        let local = InMemoryPositionStorage()
        local.recordings.set(recordingId: 1, position: 600, at: Date())
        local.vod.record(uuid: "abc", position: 300, duration: 5400, at: Date())
        let sync = makeSync(server, local)

        await sync.syncNow()
        let putsAfterFirstSync = server.puts
        await sync.syncNow()

        #expect(putsAfterFirstSync == 2)
        #expect(server.puts == putsAfterFirstSync)
        #expect(local.recordingSaves == 0 && local.vodSaves == 0)
    }

    @Test("A value on the server the app can't read is left alone")
    func unreadableValue() async {
        let server = FakeAppDataServer()
        server.store(Data(#"{"schema":"someone-else"}"#.utf8), for: DispatcharrAppData.recordingPositionsKey)
        let local = InMemoryPositionStorage()
        local.recordings.set(recordingId: 1, position: 600, at: date(0))

        await makeSync(server, local).syncNow()

        #expect(String(decoding: server.values[DispatcharrAppData.recordingPositionsKey] ?? Data(), as: UTF8.self)
                == #"{"schema":"someone-else"}"#)
    }

    // MARK: - Limits

    @Test("A store over the per-key limit is cut to its newest entries")
    func fitsPerKeyLimit() async throws {
        let server = FakeAppDataServer(kind: .current(maxValueBytes: 2_000))
        let local = InMemoryPositionStorage()
        for id in 1...200 {
            local.recordings.set(recordingId: id, position: id * 10, at: date(TimeInterval(id)))
        }

        await makeSync(server, local).syncNow()

        let uploaded = try #require(serverRecordings(server))
        #expect(uploaded.entryCount < 200)
        #expect(uploaded[200]?.position == 2000, "the newest entry is kept")
        #expect(uploaded[1] == nil, "the oldest is dropped")
        #expect(local.recordings.entryCount == 200, "the local copy keeps everything")
    }

    @Test("total_too_large is retried once with half the entries")
    func retriesWhenTotalTooLarge() async throws {
        let server = FakeAppDataServer()
        server.forcedPutStatuses = [(413, "total_too_large")]
        let local = InMemoryPositionStorage()
        for id in 1...10 {
            local.recordings.set(recordingId: id, position: 100, at: date(TimeInterval(id)))
        }

        await makeSync(server, local).syncNow()

        #expect(try #require(serverRecordings(server)).entryCount == 5)
    }

    @Test("A key the server refuses outright is left alone for the session")
    func refusedKey() async {
        let server = FakeAppDataServer()
        server.forcedPutStatuses = [(409, "max_apps"), (409, "max_apps")]
        let local = InMemoryPositionStorage()
        local.recordings.set(recordingId: 1, position: 600, at: date(0))
        local.vod.record(uuid: "abc", position: 300, duration: 5400, at: date(0))
        let sync = makeSync(server, local)

        await sync.syncNow()
        let requestsAfterFirstSync = server.requests.count
        await sync.syncNow()

        #expect(server.puts == 2)
        #expect(server.requests.count == requestsAfterFirstSync, "both keys are skipped from then on")
    }

    // MARK: - Scheduling

    @Test("Saves close together are sent as one sync")
    func debouncedSaves() async throws {
        let server = FakeAppDataServer()
        let local = InMemoryPositionStorage()
        let sync = makeSync(server, local)
        await sync.syncNow()   // probe and first upload of the empty stores
        let putsBefore = server.puts

        local.recordings.set(recordingId: 1, position: 600, at: date(0))
        sync.scheduleSync()
        local.recordings.set(recordingId: 1, position: 650, at: date(1))
        sync.scheduleSync()
        try await Task.sleep(for: .milliseconds(200))

        #expect(server.puts == putsBefore + 1)
        #expect(serverRecordings(server)?[1]?.position == 650)
    }

    @Test("Flushing sends a scheduled sync right away, and does nothing otherwise")
    func flush() async {
        let server = FakeAppDataServer()
        let local = InMemoryPositionStorage()
        let sync = DispatcharrPositionSync(
            transport: server, storage: local.storage,
            notificationCenter: NotificationCenter(), debounce: .seconds(60)
        )
        await sync.flush()
        #expect(server.requests.isEmpty)

        local.recordings.set(recordingId: 1, position: 600, at: date(0))
        sync.scheduleSync()
        await sync.flush()

        #expect(serverRecordings(server)?[1]?.position == 600)
    }

    @Test("Settings is told when the server starts or stops keeping positions")
    func supportChanges() async {
        let server = FakeAppDataServer()
        let sync = makeSync(server, InMemoryPositionStorage())
        var reported: [Bool] = []
        sync.onSupportChange = { _ in reported.append(sync.syncsWithServer) }

        await sync.syncNow()
        await sync.syncNow()
        sync.reset()

        #expect(reported == [true, false], "once when found, once when forgotten")
    }

    @Test("A reset forgets the server, so a new one is probed")
    func resetProbesAgain() async {
        let server = FakeAppDataServer(kind: .legacy)
        let sync = makeSync(server, InMemoryPositionStorage())
        await sync.syncNow()
        #expect(sync.support == .unsupported)

        server.kind = .current(maxValueBytes: 128 * 1024)
        sync.reset()
        await sync.syncNow()

        #expect(sync.support == .supported(maxValueBytes: 128 * 1024))
    }
}
