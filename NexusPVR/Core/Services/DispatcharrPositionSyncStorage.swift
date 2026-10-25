//
//  DispatcharrPositionSyncStorage.swift
//  DispatcherPVR
//
//  Where `DispatcharrPositionSync` reads and writes this device's copy of
//  the position stores (#199).
//

import Foundation

@MainActor
struct DispatcharrPositionSyncStorage {
    var loadRecordings: () -> RecordingPositionStore
    /// Saves positions that came from the server: locally and to iCloud, but
    /// without announcing them as a local edit, which would sync again.
    var saveRecordings: (RecordingPositionStore) -> Void
    var loadVOD: () -> VODProgressStore
    var saveVOD: (VODProgressStore) -> Void

    static let standard = DispatcharrPositionSyncStorage(
        loadRecordings: { RecordingPositionStore.load() },
        saveRecordings: { $0.save(announcing: false) },
        loadVOD: { VODProgressStore.load() },
        saveVOD: { $0.save(announcing: false) }
    )
}
