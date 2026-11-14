//
//  EventLogExportFile.swift
//  PVR Client
//
//  A log handed to the share sheet as a .txt file.
//

#if !os(tvOS)
import SwiftUI
import UniformTypeIdentifiers

/// A log for `ShareLink`, written to a .txt file only when the viewer
/// actually shares it.
nonisolated struct EventLogExportFile: Transferable, Sendable {
    let fileName: String
    let makeText: @Sendable () -> String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { file in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(file.fileName)
            try Data(file.makeText().utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }

    static func eventLog(events: [NetworkEvent], sessions: [UUID: PlaybackSession]) -> EventLogExportFile {
        EventLogExportFile(fileName: EventLogExporter.fileName()) {
            EventLogExporter.text(events: events, sessions: sessions)
        }
    }

    static func session(_ session: PlaybackSession) -> EventLogExportFile {
        EventLogExportFile(fileName: EventLogExporter.fileName(now: session.startedAt)) {
            EventLogExporter.text(session: session)
        }
    }
}
#endif
