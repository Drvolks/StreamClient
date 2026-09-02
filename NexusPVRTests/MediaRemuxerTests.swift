//
//  MediaRemuxerTests.swift
//  NexusPVRTests
//
//  End-to-end coverage for the libavformat remux behind offline downloads.
//
//  These need an `ffmpeg` binary to build the MPEG-TS fixture and an `ffprobe`
//  to inspect the result; both are skipped when the tools aren't installed, so
//  a machine without Homebrew still runs a green suite. macOS-only because
//  spawning those tools needs `Process`, which the simulators don't have — the
//  remuxer itself is cross-platform.
//

import Testing
import Foundation
@testable import NextPVR

#if os(macOS)

@Suite(.serialized)
struct MediaRemuxerTests {

    /// Whether the fixture tools are installed. Gates every test in the suite.
    static let toolsAvailable = tool("ffmpeg") != nil && tool("ffprobe") != nil

    // MARK: - Tool discovery

    private static func tool(_ name: String) -> URL? {
        let candidates = ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)"]
        return candidates.map(URL.init(fileURLWithPath:)).first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    @discardableResult
    private static func run(_ executable: URL, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Builds a `seconds`-long MPEG-TS with H.264 video and AAC audio — the
    /// same shape as what a Dispatcharr catch-up session serves.
    private static func makeFixture(seconds: Int, audioCodec: String = "aac", in directory: URL) throws -> URL? {
        guard let ffmpeg = tool("ffmpeg") else { return nil }
        let output = directory.appendingPathComponent("fixture-\(audioCodec).ts")
        try run(ffmpeg, [
            "-y", "-loglevel", "error",
            "-f", "lavfi", "-i", "testsrc=size=320x240:rate=25:duration=\(seconds)",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=\(seconds)",
            "-c:v", "libx264", "-preset", "ultrafast", "-g", "25",
            "-c:a", audioCodec, "-shortest",
            "-f", "mpegts", output.path
        ])
        return FileManager.default.fileExists(atPath: output.path) ? output : nil
    }

    /// Container duration in seconds, via ffprobe.
    private static func duration(of url: URL) throws -> Double? {
        guard let ffprobe = tool("ffprobe") else { return nil }
        let output = try run(ffprobe, [
            "-v", "error", "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1", url.path
        ])
        return Double(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func makeDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaRemuxerTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: - Tests

    @Test("Remuxes MPEG-TS into a playable, correctly timed MP4", .enabled(if: MediaRemuxerTests.toolsAvailable))
    func remuxesToMP4() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try #require(try Self.makeFixture(seconds: 6, in: directory))

        let result = try await MediaRemuxer().run(
            input: fixture,
            headers: [:],
            outputDirectory: directory,
            baseName: "output",
            stopAfterSeconds: nil,
            onProgress: { _, _ in }
        )

        #expect(result.url.pathExtension == "mp4")
        #expect(result.bytes > 0)
        #expect(FileManager.default.fileExists(atPath: result.url.path))
        // The whole fixture came through, give or take a frame.
        #expect(abs(result.seconds - 6) < 0.5)

        if let duration = try Self.duration(of: result.url) {
            #expect(abs(duration - 6) < 0.5)
        }
    }

    @Test("Stops at the requested duration instead of draining the whole source", .enabled(if: MediaRemuxerTests.toolsAvailable))
    func stopsAtRequestedDuration() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try #require(try Self.makeFixture(seconds: 12, in: directory))

        // This is the catch-up case in miniature: the source runs far past the
        // programme, and only the stop check ends the download.
        let result = try await MediaRemuxer().run(
            input: fixture,
            headers: [:],
            outputDirectory: directory,
            baseName: "clipped",
            stopAfterSeconds: 4,
            onProgress: { _, _ in }
        )

        #expect(result.seconds >= 4)
        #expect(result.seconds < 6)
        if let duration = try Self.duration(of: result.url) {
            #expect(duration < 6)
        }
    }

    @Test("Progress is reported while the job runs", .enabled(if: MediaRemuxerTests.toolsAvailable))
    func reportsProgress() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try #require(try Self.makeFixture(seconds: 6, in: directory))

        let reports = ProgressBox()
        _ = try await MediaRemuxer().run(
            input: fixture,
            headers: [:],
            outputDirectory: directory,
            baseName: "progress",
            stopAfterSeconds: nil,
            onProgress: { seconds, bytes in reports.record(seconds: seconds, bytes: bytes) }
        )

        // At minimum the final report lands, with real numbers in it.
        #expect(reports.count >= 1)
        #expect(reports.lastSeconds > 0)
        #expect(reports.lastBytes > 0)
    }

    @Test("Cancelling stops the job and reports it as cancelled", .enabled(if: MediaRemuxerTests.toolsAvailable))
    func cancellation() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try #require(try Self.makeFixture(seconds: 6, in: directory))

        let remuxer = MediaRemuxer()
        remuxer.cancel() // Cancelled before it starts: the loop must not run.

        await #expect(throws: MediaRemuxer.RemuxError.cancelled) {
            try await remuxer.run(
                input: fixture,
                headers: [:],
                outputDirectory: directory,
                baseName: "cancelled",
                stopAfterSeconds: nil,
                onProgress: { _, _ in }
            )
        }
    }

    @Test("A source that isn't there fails with an open error")
    func missingSource() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        await #expect(throws: (any Error).self) {
            try await MediaRemuxer().run(
                input: directory.appendingPathComponent("nope.ts"),
                headers: [:],
                outputDirectory: directory,
                baseName: "missing",
                stopAfterSeconds: nil,
                onProgress: { _, _ in }
            )
        }
    }
}

/// Collects progress callbacks, which arrive on the remuxer's own queue.
private final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var seconds: Double = 0
    private var bytes: Int64 = 0
    private var reports = 0

    func record(seconds: Double, bytes: Int64) {
        lock.lock()
        defer { lock.unlock() }
        self.seconds = seconds
        self.bytes = bytes
        reports += 1
    }

    var count: Int { lock.lock(); defer { lock.unlock() }; return reports }
    var lastSeconds: Double { lock.lock(); defer { lock.unlock() }; return seconds }
    var lastBytes: Int64 { lock.lock(); defer { lock.unlock() }; return bytes }
}
#endif
