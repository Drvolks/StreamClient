//
//  DownloadManagerTests.swift
//  NexusPVRTests
//
//  Coverage for the downloads library's in-memory state and the playback
//  position it persists.
//

import Testing
import Foundation
@testable import NextPVR

@MainActor
struct DownloadManagerTests {

    private func makeStore() -> (DownloadStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloadManagerTests-\(UUID().uuidString)", isDirectory: true)
        return (DownloadStore(directory: directory), directory)
    }

    /// A finished download, media file and all, already on disk.
    private func seedCompleted(in store: DownloadStore, directory: URL) async throws -> DownloadItem {
        var item = DownloadItem(title: "Biathlon", source: .recording(id: 1))
        item.state = .completed
        item.writtenSeconds = 3600
        try await store.save(item)
        try Data("video".utf8).write(to: directory.appendingPathComponent(item.fileName))
        return item
    }

    @Test("A playback position survives a restart")
    func positionIsPersisted() async throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = try await seedCompleted(in: store, directory: directory)

        let manager = DownloadManager(store: store)
        await manager.refresh()
        await manager.recordPlaybackPosition(1200, for: item.id)

        // In memory…
        #expect(manager.items.first?.playbackPosition == 1200)
        #expect(manager.items.first?.resumeSeconds == 1200)

        // …and on disk, which is what the next launch reads.
        let reloaded = DownloadManager(store: store)
        await reloaded.refresh()
        #expect(reloaded.items.first?.resumeSeconds == 1200)
    }

    @Test("Starting over forgets the position")
    func clearingPosition() async throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = try await seedCompleted(in: store, directory: directory)

        let manager = DownloadManager(store: store)
        await manager.refresh()
        await manager.recordPlaybackPosition(1200, for: item.id)
        await manager.clearPlaybackPosition(for: item)

        #expect(manager.items.first?.playbackPosition == nil)
        #expect(manager.items.first?.hasResumePosition == false)

        let reloaded = DownloadManager(store: store)
        await reloaded.refresh()
        #expect(reloaded.items.first?.playbackPosition == nil)
    }

    @Test("A position for something that isn't a finished download is ignored")
    func positionForUnknownItem() async throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try await seedCompleted(in: store, directory: directory)

        let manager = DownloadManager(store: store)
        await manager.refresh()
        await manager.recordPlaybackPosition(1200, for: UUID())

        #expect(manager.items.first?.playbackPosition == nil)
    }

    @Test("A position announced by the player is written down")
    func positionFromPlayerNotification() async throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = try await seedCompleted(in: store, directory: directory)

        let manager = DownloadManager(store: store)
        await manager.refresh()

        // Exactly what `PlayerView.savePlaybackPosition()` posts for a local
        // file — the seam between the player and the library.
        NotificationCenter.default.post(
            name: .downloadPositionDidChange,
            object: nil,
            userInfo: ["downloadId": item.id, "position": 900.0]
        )

        try await Task.sleep(for: .milliseconds(200))
        #expect(manager.items.first?.playbackPosition == 900)
    }

    @Test("A source already downloaded isn't offered again")
    func hasDownloadTracksCompletedItems() async throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try await seedCompleted(in: store, directory: directory)

        let manager = DownloadManager(store: store)
        await manager.refresh()

        #expect(manager.hasDownload(for: .recording(id: 1)))
        #expect(!manager.hasDownload(for: .recording(id: 2)))
    }

    @Test("A failed download is offered again")
    func failedDownloadIsOfferedAgain() async throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        var item = DownloadItem(title: "Broken", source: .recording(id: 7))
        item.state = .failed(message: "Writing failed")
        try await store.save(item)

        let manager = DownloadManager(store: store)
        await manager.refresh()

        #expect(manager.items.count == 1)
        #expect(!manager.hasDownload(for: .recording(id: 7)))
    }
}
