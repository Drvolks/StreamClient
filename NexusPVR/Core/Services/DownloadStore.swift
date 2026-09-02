//
//  DownloadStore.swift
//  NexusPVR
//
//  On-disk home of the offline downloads library.
//

import Foundation

/// Owns the downloads directory and the JSON sidecars that describe what is in
/// it.
///
/// The library lives in the app's own container (Application Support), which
/// the macOS sandbox allows without any file-access entitlement. State is kept
/// per file rather than in one index so it can never describe a file that isn't
/// there — `scan()` simply reads whatever sidecars exist. It is deliberately
/// local: unlike `UserPreferences`, a downloaded file belongs to this machine
/// and must not travel through iCloud.
actor DownloadStore {

    enum StoreError: LocalizedError {
        case noDirectory

        var errorDescription: String? {
            switch self {
            case .noDirectory: return "Couldn't find a place to store downloads."
            }
        }
    }

    private let fileManager = FileManager.default
    private let directoryOverride: URL?

    /// - Parameter directory: only for tests, which need a temporary location.
    init(directory: URL? = nil) {
        self.directoryOverride = directory
    }

    /// The downloads directory, created on first use.
    func directory() throws -> URL {
        if let directoryOverride {
            try fileManager.createDirectory(at: directoryOverride, withIntermediateDirectories: true)
            return directoryOverride
        }
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw StoreError.noDirectory
        }
        let bundleId = Bundle.main.bundleIdentifier ?? "NexusPVR"
        let directory = base.appendingPathComponent(bundleId, isDirectory: true)
            .appendingPathComponent("Downloads", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func mediaURL(for item: DownloadItem) throws -> URL {
        try directory().appendingPathComponent(item.fileName)
    }

    /// Writes (or rewrites) an item's sidecar.
    func save(_ item: DownloadItem) throws {
        let url = try directory().appendingPathComponent(item.metadataFileName)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(item).write(to: url, options: .atomic)
    }

    /// Rebuilds the library from disk, newest first.
    ///
    /// Two kinds of repair happen here. An item still marked `running` or
    /// `queued` was interrupted by the app quitting — nothing is resuming it,
    /// so it is reported as failed. An item marked `completed` whose media file
    /// has been deleted from under us (by the user, in Finder) is dropped along
    /// with its sidecar.
    ///
    /// - Parameter preserving: ids the caller is actively downloading right
    ///   now. Those are returned untouched — repairing them would declare a
    ///   live download dead.
    func scan(preserving: Set<UUID> = []) throws -> [DownloadItem] {
        let directory = try directory()
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var items: [DownloadItem] = []
        for url in contents where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  var item = try? decoder.decode(DownloadItem.self, from: data) else {
                continue
            }
            let mediaURL = directory.appendingPathComponent(item.fileName)
            let mediaExists = fileManager.fileExists(atPath: mediaURL.path)

            if item.state.isActive && !preserving.contains(item.id) {
                item.state = .failed(message: "Interrupted — the app quit before this finished.")
                try? save(item)
            }
            if item.state == .completed && !mediaExists {
                try? fileManager.removeItem(at: url)
                continue
            }
            items.append(item)
        }
        return items.sorted { $0.createdAt > $1.createdAt }
    }

    /// Removes both the media file and its sidecar. Missing files are not an
    /// error — the point is that afterwards neither exists.
    func delete(_ item: DownloadItem) throws {
        let directory = try directory()
        try? fileManager.removeItem(at: directory.appendingPathComponent(item.fileName))
        try? fileManager.removeItem(at: directory.appendingPathComponent(item.metadataFileName))
    }

    /// Free space available for downloads, used as a pre-flight check.
    /// tvOS has no "important usage" capacity key — downloads aren't offered
    /// there anyway, so the plain volume capacity keeps the file compiling.
    func availableBytes() -> Int64? {
        guard let directory = try? directory() else { return nil }
        #if os(tvOS)
        guard let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
              let capacity = values.volumeAvailableCapacity else {
            return nil
        }
        return Int64(capacity)
        #else
        guard let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]) else {
            return nil
        }
        return values.volumeAvailableCapacityForImportantUsage
        #endif
    }
}
