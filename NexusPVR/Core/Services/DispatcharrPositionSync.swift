//
//  DispatcharrPositionSync.swift
//  DispatcherPVR
//
//  Keeps a copy of the recording and On Demand positions in Dispatcharr's
//  per-user app data (#199), next to the local and iCloud copies (#183).
//  Positions then follow the Dispatcharr user: people sharing a server but
//  not an Apple ID, or a device signed out of iCloud, still pick up where
//  they left off.
//
//  The server has no locking or partial update, so each sync reads the key,
//  merges it into the local copy (newest entry wins), then writes the merged
//  result back. A write lost to another device is repaired by the next
//  merge, and since a reset is stored as position 0 rather than removed, a
//  lost write can't bring a cleared position back.
//

import Foundation

@MainActor
final class DispatcharrPositionSync {
    private weak var transport: (any DispatcharrAppDataTransport)?
    private let storage: DispatcharrPositionSyncStorage
    private let notificationCenter: NotificationCenter
    private let debounce: Duration

    /// nil until probed, once per session.
    private(set) var support: DispatcharrAppData.Support? {
        didSet {
            if support != oldValue { onSupportChange?(support) }
        }
    }
    /// Called when `support` changes, so Settings can say where positions
    /// are kept.
    var onSupportChange: ((DispatcharrAppData.Support?) -> Void)?
    /// Whether positions are being kept on the server too.
    var syncsWithServer: Bool {
        if case .supported = support { return true }
        return false
    }
    /// Entry caps learned from `value_too_large` / `total_too_large`, so the
    /// next sync doesn't send a value the server just refused.
    private var serverEntryCaps: [String: Int] = [:]
    /// Keys the server refused for a reason pruning can't fix (`max_apps`,
    /// a rejected value): left alone for the rest of the session.
    private var refusedKeys: Set<String> = []
    private var lastSync: Task<Void, Never>?
    private var pendingSync: Task<Void, Never>?
    private var observer: (any NSObjectProtocol)?

    init(transport: any DispatcharrAppDataTransport,
         storage: DispatcharrPositionSyncStorage = .standard,
         notificationCenter: NotificationCenter = .default,
         debounce: Duration = .seconds(3)) {
        self.transport = transport
        self.storage = storage
        self.notificationCenter = notificationCenter
        self.debounce = debounce
    }

    /// Call once at launch: from then on a position saved on this device is
    /// sent to the server shortly after.
    func start() {
        guard observer == nil else { return }
        observer = notificationCenter.addObserver(
            forName: .playbackPositionSaved, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleSync() }
        }
    }

    /// Forgets what is known about the server, for a new server or account.
    func reset() {
        pendingSync?.cancel()
        pendingSync = nil
        support = nil
        serverEntryCaps = [:]
        refusedKeys = []
    }

    /// Syncs a few seconds from now. Pausing and closing the player both save,
    /// so this sends one request for the pair instead of two.
    func scheduleSync() {
        pendingSync?.cancel()
        pendingSync = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled, let self else { return }
            self.pendingSync = nil
            await self.syncNow()
        }
    }

    /// Sends a scheduled sync right away, before the app is suspended.
    func flush() async {
        guard pendingSync != nil else { return }
        await syncNow()
    }

    /// Reads, merges and writes both stores. Syncs run one at a time.
    func syncNow() async {
        pendingSync?.cancel()
        pendingSync = nil
        let previous = lastSync
        let sync = Task { [weak self] in
            await previous?.value
            await self?.performSync()
        }
        lastSync = sync
        await sync.value
    }

    private func performSync() async {
        guard transport?.appDataSyncAllowed == true,
              let maxBytes = await resolveMaxValueBytes() else { return }
        if await sync(DispatcharrAppData.recordingPositionsKey, maxBytes: maxBytes,
                      load: storage.loadRecordings, save: storage.saveRecordings) {
            notificationCenter.post(name: .recordingsDidChange, object: nil)
        }
        if await sync(DispatcharrAppData.vodProgressKey, maxBytes: maxBytes,
                      load: storage.loadVOD, save: storage.saveVOD) {
            notificationCenter.post(name: .vodProgressDidChange, object: nil)
        }
    }

    private func resolveMaxValueBytes() async -> Int? {
        if support == nil, let transport {
            do {
                let response = try await transport.appDataResponse(key: nil, method: "GET", body: nil)
                support = DispatcharrAppData.support(status: response.status, data: response.data)
                if let support {
                    print("[PositionSync] Server app data \(support == .unsupported ? "not available, iCloud only" : "available")")
                }
            } catch {
                print("[PositionSync] Probe failed: \(error.localizedDescription)")
            }
        }
        guard case .supported(let maxValueBytes) = support else { return nil }
        return maxValueBytes
    }

    /// Syncs one key. Returns whether the local copy changed.
    private func sync<Store: ServerSyncedPositionStore>(
        _ key: String,
        maxBytes: Int,
        load: () -> Store,
        save: (Store) -> Void
    ) async -> Bool {
        guard !refusedKeys.contains(key), let transport else { return false }

        let server: Store?
        do {
            let response = try await transport.appDataResponse(key: key, method: "GET", body: nil)
            switch response.status {
            case 200:
                guard let decoded = DispatcharrAppData.decode(Store.self, from: response.data) else {
                    // Not ours to overwrite blindly; leave it for a later version.
                    print("[PositionSync] \(key): unreadable value on the server, left alone")
                    refusedKeys.insert(key)
                    return false
                }
                server = decoded
            case 404 where DispatcharrAppData.errorCode(in: response.data) == DispatcharrAppDataErrorBody.keyNotFound:
                server = nil
            case 404:
                support = .unsupported
                return false
            default:
                print("[PositionSync] \(key): GET answered \(response.status)")
                return false
            }
        } catch {
            print("[PositionSync] \(key): GET failed: \(error.localizedDescription)")
            return false
        }

        // No suspension from here to `save`, so a position the player saved
        // while the request was out is part of what gets merged.
        let local = load()
        var merged = local
        if let server { merged.merge(server) }
        let localChanged = merged != local
        if localChanged { save(merged) }

        await push(merged, to: key, maxBytes: maxBytes, serverCopy: server)
        return localChanged
    }

    private func push<Store: ServerSyncedPositionStore>(
        _ store: Store,
        to key: String,
        maxBytes: Int,
        serverCopy: Store?
    ) async {
        guard var fit = DispatcharrAppData.fitted(store, maxBytes: maxBytes, maxEntries: serverEntryCaps[key]) else {
            return
        }
        guard fit.store != serverCopy else { return }

        for attempt in 0..<2 {
            guard let transport else { return }
            let status: Int
            let code: String?
            do {
                let response = try await transport.appDataResponse(key: key, method: "PUT", body: fit.data)
                status = response.status
                code = DispatcharrAppData.errorCode(in: response.data)
            } catch {
                print("[PositionSync] \(key): PUT failed: \(error.localizedDescription)")
                return
            }
            switch status {
            case 200...299:
                return
            case 413 where attempt == 0:
                // Over the per-key limit, or the user's total shared with
                // other apps: try once with half the entries.
                let cap = max(fit.store.entryCount / 2, 1)
                serverEntryCaps[key] = cap
                guard let smaller = DispatcharrAppData.fitted(store, maxBytes: maxBytes, maxEntries: cap) else { return }
                fit = smaller
                print("[PositionSync] \(key): \(code ?? "413"), retrying with \(cap) entries")
            case 413:
                print("[PositionSync] \(key): still too large, iCloud only for this session")
                refusedKeys.insert(key)
                return
            case 400, 403, 409:
                print("[PositionSync] \(key): PUT refused (\(status) \(code ?? "")), iCloud only for this session")
                refusedKeys.insert(key)
                return
            default:
                // A server error or the like: the next sync tries again.
                print("[PositionSync] \(key): PUT answered \(status)")
                return
            }
        }
    }
}
