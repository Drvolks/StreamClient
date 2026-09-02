//
//  DownloadItemTests.swift
//  NexusPVRTests
//
//  Coverage for the offline download metadata model.
//

import Testing
import Foundation
@testable import NextPVR

struct DownloadItemTests {

    private func program(start: Date, minutes: Int) -> Program {
        Program(
            id: 7,
            name: "Test Show",
            subtitle: "Pilot",
            desc: nil,
            start: Int(start.timeIntervalSince1970),
            end: Int(start.timeIntervalSince1970) + minutes * 60,
            genres: nil,
            channelId: 42
        )
    }

    private var channel: Channel {
        Channel(id: 42, name: "BBC One", number: 1, hasIcon: true)
    }

    @Test("File names are derived from the id, so nothing has to be escaped")
    func fileNames() {
        let item = DownloadItem(title: "A / B: \"C\"", source: .recording(id: 1))
        #expect(item.fileName == "\(item.id.uuidString).mp4")
        #expect(item.metadataFileName == "\(item.id.uuidString).json")
        // The awkward characters live in the title, not on disk.
        #expect(!item.fileName.contains("/"))
    }

    @Test("A Matroska fallback is remembered in the file name")
    func matroskaFallback() {
        var item = DownloadItem(title: "Show", source: .recording(id: 1))
        item.fileExtension = "mkv"
        #expect(item.fileName == "\(item.id.uuidString).mkv")
    }

    @Test("Display title joins the episode when there is one")
    func displayTitle() {
        #expect(DownloadItem(title: "Show", subtitle: "Pilot", source: .recording(id: 1)).displayTitle == "Show - Pilot")
        #expect(DownloadItem(title: "Show", subtitle: nil, source: .recording(id: 1)).displayTitle == "Show")
        #expect(DownloadItem(title: "Show", subtitle: "", source: .recording(id: 1)).displayTitle == "Show")
    }

    @Test("A catch-up item asks for the programme length plus a tail")
    func catchupExpectedDuration() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let item = DownloadItem.catchup(
            program: program(start: start, minutes: 30),
            channel: channel,
            channelUuid: "uuid-1"
        )
        #expect(item.expectedDuration == 1800 + DownloadPolicy.catchupTailSeconds)
        // Catch-up is the case that must stop itself: its archive runs to the
        // moment the session was minted, not to the end of the programme.
        #expect(item.stopAfterSeconds == 1800 + DownloadPolicy.catchupTailSeconds)
        #expect(item.source == .catchup(channelUuid: "uuid-1", start: start))
        #expect(item.channelName == "BBC One")
        #expect(item.state == .queued)
    }

    @Test("A recording knows its length for the progress bar but isn't cut short by it")
    func recordingDurationDrivesProgressOnly() {
        let recording = Recording(
            id: 99,
            name: "Recorded Show",
            subtitle: "Episode 2",
            startTime: 1_700_000_000,
            duration: 3600,
            channel: "ITV",
            prePadding: 1,
            postPadding: 2
        )
        let item = DownloadItem.recording(recording)
        // Padded length (3600 + 1 min pre + 2 min post): that's what the file
        // actually holds, so it's what the progress bar should measure against.
        #expect(item.expectedDuration == 3780.0)
        // But nothing stops it early — that would truncate the post-padding.
        #expect(item.stopAfterSeconds == nil)
        #expect(item.source == .recording(id: 99))
        #expect(item.channelName == "ITV")
    }

    @Test("A recording with no reported duration still downloads")
    func recordingWithoutDuration() {
        let recording = Recording(id: 100, name: "Unknown length")
        let item = DownloadItem.recording(recording)
        #expect(item.expectedDuration == nil)
        #expect(item.stopAfterSeconds == nil)
    }

    @Test("Round-trips through JSON, including the state and source")
    func codableRoundTrip() throws {
        // Whole-second dates: the store encodes ISO-8601, which has no room for
        // fractional seconds, and nothing here needs finer than that.
        var item = DownloadItem(
            title: "Test Show",
            subtitle: "Pilot",
            channelName: "BBC One",
            programStart: Date(timeIntervalSince1970: 1_700_000_000),
            programEnd: Date(timeIntervalSince1970: 1_700_003_600),
            expectedDuration: 3660,
            source: .catchup(channelUuid: "uuid-2", start: Date(timeIntervalSince1970: 1_700_000_000)),
            createdAt: Date(timeIntervalSince1970: 1_700_010_000)
        )
        item.state = .running(seconds: 12.5, bytes: 4096)
        item.writtenSeconds = 12.5
        item.byteSize = 4096

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(DownloadItem.self, from: encoder.encode(item))
        #expect(decoded == item)
        #expect(decoded.state == .running(seconds: 12.5, bytes: 4096))
    }

    @Test("Resume only kicks in past the first few seconds")
    func resumeThreshold() {
        var item = DownloadItem(title: "Show", source: .recording(id: 1))
        item.writtenSeconds = 3600

        item.playbackPosition = nil
        #expect(item.resumeSeconds == nil)

        // A few seconds in is a false start, not a place to come back to.
        item.playbackPosition = 5
        #expect(item.resumeSeconds == nil)
        #expect(!item.hasResumePosition)

        item.playbackPosition = 1200
        #expect(item.resumeSeconds == 1200)
        #expect(item.hasResumePosition)
    }

    @Test("Finishing a programme starts the next play from the beginning")
    func resumeNearTheEnd() {
        var item = DownloadItem(title: "Show", source: .recording(id: 1))
        item.writtenSeconds = 3600

        // Dropping the viewer on the closing credits is worse than starting over.
        item.playbackPosition = 3590
        #expect(item.resumeSeconds == nil)

        item.playbackPosition = 3600 - DownloadItem.finishedTailSeconds - 1
        #expect(item.resumeSeconds != nil)
    }

    @Test("A position is still usable when the duration isn't known")
    func resumeWithoutDuration() {
        var item = DownloadItem(title: "Show", source: .recording(id: 1))
        item.writtenSeconds = nil
        item.playbackPosition = 1200
        #expect(item.resumeSeconds == 1200)
    }

    @Test("Only running and queued count as active")
    func activeStates() {
        #expect(DownloadState.queued.isActive)
        #expect(DownloadState.running(seconds: 1, bytes: 1).isActive)
        #expect(!DownloadState.completed.isActive)
        #expect(!DownloadState.failed(message: "boom").isActive)
    }
}
