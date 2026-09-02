//
//  DownloadManager.swift
//  NexusPVR
//
//  Queues, runs and tracks offline downloads.
//

import Combine
import Foundation
#if os(iOS)
import UIKit
#endif

/// The Downloads feature's view-facing state and engine.
///
/// Downloads run one at a time. The bottleneck is the server, and a catch-up
/// session holds a tuner-like resource on it for as long as it is open, so
/// there is nothing to gain from running two at once and a real risk in it.
@MainActor
final class DownloadManager: ObservableObject {

    @Published private(set) var items: [DownloadItem] = [] {
        didSet { publishActiveCount() }
    }

    /// Set once at startup so the sidebar badge can track activity without
    /// observing this manager (and so re-rendering on every progress tick).
    weak var appState: AppState?

    /// The downloads directory, cached from the store so views can build file
    /// URLs without awaiting the actor.
    @Published private(set) var directory: URL?
    /// Set when starting a download fails outright (no space, no catch-up
    /// metadata); the view shows it in an alert and clears it.
    @Published var startError: String?

    private let store: DownloadStore
    private var runningItemId: UUID?
    private var activeRemuxer: MediaRemuxer?
    /// Set while a job is being torn down so its own state writes don't get
    /// mistaken for a fresh failure.
    private var cancelledItemIds: Set<UUID> = []

    init(store: DownloadStore = DownloadStore()) {
        self.store = store
        // The player doesn't know where downloads live, so it announces the
        // position and this writes it down.
        //
        // The token is deliberately not kept for removal: a `@MainActor` type's
        // `deinit` is nonisolated and can't touch the non-`Sendable` token, and
        // the app holds exactly one manager for its whole lifetime. The weak
        // capture makes an outlived registration a no-op.
        NotificationCenter.default.addObserver(
            forName: .downloadPositionDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let id = notification.userInfo?["downloadId"] as? UUID,
                  let position = notification.userInfo?["position"] as? Double else {
                return
            }
            Task { @MainActor [weak self] in
                await self?.recordPlaybackPosition(position, for: id)
            }
        }
    }

    /// Stores how far playback got, so the next Play resumes there.
    func recordPlaybackPosition(_ position: Double, for id: UUID) async {
        guard items.contains(where: { $0.id == id && $0.state == .completed }) else { return }
        update(id) { $0.playbackPosition = position }
        await persist(id)
    }

    /// Forgets the position, so playback starts from the beginning again.
    func clearPlaybackPosition(for item: DownloadItem) async {
        update(item.id) { $0.playbackPosition = nil }
        await persist(item.id)
    }

    /// How many downloads are queued or running, for the sidebar badge.
    var activeCount: Int { items.filter { $0.state.isActive }.count }

    private func publishActiveCount() {
        // No downloads UI on tvOS, so no badge to feed.
        #if !os(tvOS)
        guard let appState else { return }
        let count = activeCount
        // Only on a real change: `items` is rewritten on every progress tick.
        if appState.activeDownloadCount != count {
            appState.activeDownloadCount = count
        }
        #endif
    }

    /// Whether this source is already downloading or downloaded, so the UI can
    /// say "Downloaded" instead of offering it again. A failed attempt doesn't
    /// count — that one is worth offering again.
    func hasDownload(for source: DownloadSource) -> Bool {
        items.contains { $0.source == source && ($0.state.isActive || $0.state == .completed) }
    }

    /// Loads the library from disk. Cheap enough to call on every appearance.
    ///
    /// Anything this manager is currently downloading is kept as it stands in
    /// memory: on disk a running item still reads as `queued` (progress isn't
    /// written per packet), so a plain re-read would mistake a live download
    /// for one the app abandoned and report it as interrupted.
    func refresh() async {
        do {
            directory = try? await store.directory()
            let inFlight = items.filter { $0.state.isActive }
            let inFlightIds = Set(inFlight.map(\.id))
            let stored = try await store.scan(preserving: inFlightIds)
            items = (inFlight + stored.filter { !inFlightIds.contains($0.id) })
                .sorted { $0.createdAt > $1.createdAt }
        } catch {
            startError = error.localizedDescription
        }
    }

    /// Local file URL for a finished download. Synchronous because the rows
    /// need it while building their body — `ShareLink` wants the URL up front,
    /// not from a task.
    func fileURL(for item: DownloadItem) -> URL? {
        directory?.appendingPathComponent(item.fileName)
    }

    // MARK: - Enqueuing

    #if DISPATCHERPVR
    /// Queues an aired catch-up programme. `channelUuid` comes from
    /// `DispatcherClient.channelUUID(forChannelId:)` — without it the server
    /// can't mint a session, so the caller must resolve it first.
    func download(program: Program, channel: Channel, channelUuid: String, using client: PVRClient) async {
        let item = DownloadItem.catchup(program: program, channel: channel, channelUuid: channelUuid)
        await enqueue(item, using: client)
    }
    #endif

    /// Queues a completed server recording.
    func download(recording: Recording, using client: PVRClient) async {
        let item = DownloadItem.recording(recording)
        await enqueue(item, using: client)
    }

    /// Starts a failed download over. The source is re-resolved from scratch —
    /// a catch-up session's archive offset is fixed at mint time, so there is
    /// no byte offset worth resuming from.
    func retry(_ item: DownloadItem, using client: PVRClient) async {
        guard !item.state.isActive else { return }
        try? await store.delete(item)
        var fresh = item
        fresh.state = .queued
        fresh.writtenSeconds = nil
        fresh.byteSize = nil
        fresh.fileExtension = "mp4"
        items.removeAll { $0.id == item.id }
        await enqueue(fresh, using: client)
    }

    private func enqueue(_ item: DownloadItem, using client: PVRClient) async {
        if let available = await store.availableBytes(), available < DownloadPolicy.minimumFreeBytes {
            startError = "Not enough free disk space to start this download."
            return
        }
        do {
            try await store.save(item)
        } catch {
            startError = error.localizedDescription
            return
        }
        items.insert(item, at: 0)
        await startNextIfIdle(using: client)
    }

    // MARK: - Running

    private func startNextIfIdle(using client: PVRClient) async {
        guard runningItemId == nil else { return }
        // Oldest queued first: new items are inserted at the front of `items`
        // so the list reads newest-first, which makes the tail the queue head.
        while let next = items.last(where: { $0.state == .queued }) {
            runningItemId = next.id
            await run(next, using: client)
            runningItemId = nil
        }
    }

    private func run(_ item: DownloadItem, using client: PVRClient) async {
        var sessionId: String?
        #if os(iOS)
        // Buys the job a grace period when the user switches away. iOS suspends
        // the app soon after, which kills an in-process download — the sidecar
        // is then repaired to "interrupted" on next launch (`DownloadStore.scan`)
        // so it reads as failed rather than silently stalled.
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Offline download")
        defer {
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
            }
        }
        #endif
        do {
            let resolved = try await resolve(item, using: client)
            sessionId = resolved.sessionId
            update(item.id) { $0.state = .running(seconds: 0, bytes: 0) }

            let remuxer = MediaRemuxer()
            activeRemuxer = remuxer
            defer { activeRemuxer = nil }

            let directory = try await store.directory()
            self.directory = directory
            let itemId = item.id
            let result = try await remuxer.run(
                input: resolved.url,
                headers: resolved.headers,
                outputDirectory: directory,
                baseName: item.id.uuidString,
                stopAfterSeconds: item.stopAfterSeconds,
                onProgress: { [weak self] seconds, bytes in
                    Task { @MainActor [weak self] in
                        self?.update(itemId) { $0.state = .running(seconds: seconds, bytes: bytes) }
                    }
                }
            )

            await endCatchupSession(sessionId, using: client)
            sessionId = nil

            guard DownloadPolicy.isUsable(writtenSeconds: result.seconds) else {
                await fail(item.id, message: "The server returned no usable video.")
                return
            }
            update(item.id) {
                $0.state = .completed
                $0.writtenSeconds = result.seconds
                $0.byteSize = result.bytes
                $0.fileExtension = result.url.pathExtension
            }
            await persist(item.id)
        } catch {
            await endCatchupSession(sessionId, using: client)
            if cancelledItemIds.remove(item.id) != nil {
                items.removeAll { $0.id == item.id }
                try? await store.delete(item)
            } else {
                await fail(item.id, message: error.localizedDescription)
            }
        }
    }

    /// Resolves the item's source into something the remuxer can open.
    private func resolve(
        _ item: DownloadItem,
        using client: PVRClient
    ) async throws -> (url: URL, headers: [String: String], sessionId: String?) {
        switch item.source {
        case .recording(let id):
            let url = try await client.recordingStreamURL(recordingId: id)
            return (url, client.streamAuthHeaders(), nil)

        case .catchup(let channelUuid, let start):
            #if DISPATCHERPVR
            // Minted here rather than at enqueue time: the server gives 60
            // seconds between minting and the first byte read
            // (`CatchupService.handshakeTTLSeconds`), which a queued download
            // would blow straight through.
            let service = CatchupService(client: client, baseURL: client.baseURL)
            let formatter = ISO8601DateFormatter()
            let session = try await service.startSession(
                channelUuid: channelUuid,
                startISO8601: formatter.string(from: start)
            )
            let url = try service.playbackURL(for: session)
            return (url, client.streamAuthHeaders(), session.sessionId)
            #else
            throw DownloadError.catchupUnsupported
            #endif
        }
    }

    private func endCatchupSession(_ sessionId: String?, using client: PVRClient) async {
        #if DISPATCHERPVR
        guard let sessionId else { return }
        let service = CatchupService(client: client, baseURL: client.baseURL)
        await service.endSession(sessionId)
        #else
        _ = sessionId
        _ = client
        #endif
    }

    // MARK: - Cancel / delete

    /// Stops a running or queued download and removes it from the library. A
    /// half-written file is of no use to anyone, so it goes too.
    func cancel(_ item: DownloadItem) async {
        if runningItemId == item.id {
            cancelledItemIds.insert(item.id)
            activeRemuxer?.cancel()
            return
        }
        items.removeAll { $0.id == item.id }
        try? await store.delete(item)
    }

    func delete(_ item: DownloadItem) async {
        if item.state.isActive {
            await cancel(item)
            return
        }
        items.removeAll { $0.id == item.id }
        try? await store.delete(item)
    }

    // MARK: - State plumbing

    private func update(_ id: UUID, _ change: (inout DownloadItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
    }

    private func persist(_ id: UUID) async {
        guard let item = items.first(where: { $0.id == id }) else { return }
        try? await store.save(item)
    }

    private func fail(_ id: UUID, message: String) async {
        update(id) { $0.state = .failed(message: message) }
        await persist(id)
    }

    enum DownloadError: LocalizedError {
        case catchupUnsupported

        var errorDescription: String? {
            switch self {
            case .catchupUnsupported: return "Catch-up downloads aren't available for this server."
            }
        }
    }
}
