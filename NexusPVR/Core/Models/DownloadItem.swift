//
//  DownloadItem.swift
//  NexusPVR
//
//  Metadata for one offline download, persisted as a JSON sidecar next to the
//  media file it describes.
//

import Foundation

/// One entry in the Downloads library.
///
/// Persisted as `<id>.json` beside `<id>.mp4` rather than in a central index:
/// a per-file sidecar can't drift out of sync with what is actually on disk,
/// and `DownloadStore.scan()` rebuilds the whole library by reading them.
/// Deliberately device-local — a file on this Mac has no business syncing
/// through iCloud KVS the way `UserPreferences` does.
nonisolated struct DownloadItem: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    /// Programme or recording title, shown as the row's primary line.
    let title: String
    /// Episode title, where the source had one.
    let subtitle: String?
    let channelName: String?
    /// Scheduled broadcast window, for display and for `expectedDuration`.
    let programStart: Date?
    let programEnd: Date?
    /// How much programme this download should contain, in seconds. `nil` for
    /// sources that end on their own (a recording file), which also means
    /// progress can only be reported in bytes.
    let expectedDuration: Double?
    let source: DownloadSource
    let createdAt: Date
    /// Seconds of programme actually written, filled in when the job ends.
    var writtenSeconds: Double?
    /// Size on disk in bytes, filled in when the job ends.
    var byteSize: Int64?
    var state: DownloadState

    /// Container the file was written in. Normally `mp4`; `MediaRemuxer` falls
    /// back to Matroska for codecs MP4 has no tag for, and the library has to
    /// remember which one it got.
    var fileExtension: String

    /// The media file's name inside the downloads directory. Derived from `id`
    /// rather than the title so nothing has to be escaped, sanitised, or
    /// de-duplicated — the human-readable name lives in `title`.
    var fileName: String { "\(id.uuidString).\(fileExtension)" }

    /// The sidecar's file name.
    var metadataFileName: String { "\(id.uuidString).json" }

    /// Title and episode joined the way rows and the player title bar want it.
    var displayTitle: String {
        guard let subtitle, !subtitle.isEmpty else { return title }
        return "\(title) - \(subtitle)"
    }

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String? = nil,
        channelName: String? = nil,
        programStart: Date? = nil,
        programEnd: Date? = nil,
        expectedDuration: Double? = nil,
        source: DownloadSource,
        createdAt: Date = Date(),
        writtenSeconds: Double? = nil,
        byteSize: Int64? = nil,
        fileExtension: String = "mp4",
        state: DownloadState = .queued
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.channelName = channelName
        self.programStart = programStart
        self.programEnd = programEnd
        self.expectedDuration = expectedDuration
        self.source = source
        self.createdAt = createdAt
        self.writtenSeconds = writtenSeconds
        self.byteSize = byteSize
        self.fileExtension = fileExtension
        self.state = state
    }
}

extension DownloadItem {
    /// Builds the entry for a Dispatcharr catch-up programme.
    ///
    /// `expectedDuration` is the programme length plus
    /// `DownloadPolicy.catchupTailSeconds`, because a catch-up session's
    /// archive runs from the programme's start all the way to the moment the
    /// session was minted — for a show that aired two days ago that is two days
    /// of content, so the download has to stop itself.
    static func catchup(program: Program, channel: Channel, channelUuid: String) -> DownloadItem {
        DownloadItem(
            title: program.cleanName,
            subtitle: program.subtitle,
            channelName: channel.name,
            programStart: program.startDate,
            programEnd: program.endDate,
            expectedDuration: program.duration + DownloadPolicy.catchupTailSeconds,
            source: .catchup(channelUuid: channelUuid, start: program.startDate)
        )
    }

    /// Builds the entry for a completed server recording. No duration cap: the
    /// recording is a finite file that ends on its own.
    static func recording(_ recording: Recording) -> DownloadItem {
        DownloadItem(
            title: recording.cleanName,
            subtitle: recording.subtitle,
            channelName: recording.channel,
            programStart: recording.startDate,
            programEnd: recording.endDate,
            expectedDuration: nil,
            source: .recording(id: recording.id)
        )
    }
}
