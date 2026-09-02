//
//  DownloadStoreTests.swift
//  NexusPVRTests
//
//  Coverage for the on-disk downloads library.
//

import Testing
import Foundation
@testable import NextPVR

struct DownloadStoreTests {

    /// Each test gets its own throwaway directory; the store creates it.
    private func makeStore() -> (DownloadStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloadStoreTests-\(UUID().uuidString)", isDirectory: true)
        return (DownloadStore(directory: directory), directory)
    }

    private func writeMedia(for item: DownloadItem, in directory: URL) throws {
        try Data("video".utf8).write(to: directory.appendingPathComponent(item.fileName))
    }

    @Test("Saved items come back from a scan, newest first")
    func saveAndScan() async throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        var older = DownloadItem(title: "Older", source: .recording(id: 1), createdAt: Date(timeIntervalSince1970: 1000))
        older.state = .completed
        var newer = DownloadItem(title: "Newer", source: .recording(id: 2), createdAt: Date(timeIntervalSince1970: 2000))
        newer.state = .completed

        try await store.save(older)
        try await store.save(newer)
        try writeMedia(for: older, in: directory)
        try writeMedia(for: newer, in: directory)

        let items = try await store.scan()
        #expect(items.map(\.title) == ["Newer", "Older"])
    }

    @Test("A download interrupted by the app quitting is reported as failed")
    func interruptedDownloadRepaired() async throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        var running = DownloadItem(title: "Interrupted", source: .recording(id: 3))
        running.state = .running(seconds: 30, bytes: 1024)
        try await store.save(running)
        try writeMedia(for: running, in: directory)

        let items = try await store.scan()
        #expect(items.count == 1)
        if case .failed = items[0].state {
            // The repair is also written back, so a second scan agrees.
            let again = try await store.scan()
            if case .failed = again[0].state {} else {
                Issue.record("Repaired state was not persisted")
            }
        } else {
            Issue.record("Expected an interrupted download to be marked failed, got \(items[0].state)")
        }
    }

    @Test("A download that's still running isn't mistaken for an interrupted one")
    func preservedDownloadNotRepaired() async throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        // On disk a live download still reads as queued — progress isn't
        // written per packet — so the manager tells the scan to leave it alone.
        let live = DownloadItem(title: "In flight", source: .recording(id: 8))
        try await store.save(live)
        try writeMedia(for: live, in: directory)

        let items = try await store.scan(preserving: [live.id])
        #expect(items.count == 1)
        #expect(items[0].state == .queued)

        // And nothing was written back, so a later scan still sees it queued.
        let again = try await store.scan(preserving: [live.id])
        #expect(again[0].state == .queued)
    }

    @Test("A completed item whose file was deleted in Finder drops out of the library")
    func missingMediaDropped() async throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        var completed = DownloadItem(title: "Gone", source: .recording(id: 4))
        completed.state = .completed
        try await store.save(completed)
        // Deliberately no media file.

        #expect(try await store.scan().isEmpty)
        // Its sidecar is cleaned up too, so it can't come back.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(leftovers.isEmpty)
    }

    @Test("Delete removes both the media file and the sidecar")
    func deleteRemovesBoth() async throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        var item = DownloadItem(title: "Doomed", source: .recording(id: 5))
        item.state = .completed
        try await store.save(item)
        try writeMedia(for: item, in: directory)

        try await store.delete(item)

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(leftovers.isEmpty)
        #expect(try await store.scan().isEmpty)
    }

    @Test("Deleting something that isn't there is not an error")
    func deleteMissingIsFine() async throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        try await store.delete(DownloadItem(title: "Never existed", source: .recording(id: 6)))
    }

    @Test("Non-JSON files in the directory are ignored")
    func ignoresStrayFiles() async throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = try await store.directory()
        try Data("not ours".utf8).write(to: directory.appendingPathComponent("stray.mp4"))

        #expect(try await store.scan().isEmpty)
    }
}
