//
//  RecordingsViewModelParsersTests.swift
//  NexusPVRTests
//
//  Tests for RecordingsViewModel's nonisolated static media probe helpers
//  (MP4 mvhd parsing, MKV segment info parsing, and MPEG-TS PTS extraction).
//
//  These are pure functions: Data in → Int/UInt64/String out. We construct
//  minimal binary buffers that hit each code path.
//

import Testing
import Foundation
@testable import NextPVR

struct RecordingsViewModelParsersTests {

    // MARK: - Binary helpers

    /// Build a big-endian 4-byte representation of a UInt32.
    private func be32(_ value: UInt32) -> [UInt8] {
        [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ]
    }

    /// Build a big-endian 8-byte representation of a UInt64.
    private func be64(_ value: UInt64) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 8)
        for i in 0..<8 {
            out[i] = UInt8((value >> UInt64((7 - i) * 8)) & 0xFF)
        }
        return out
    }

    private func fourcc(_ s: String) -> [UInt8] {
        Array(s.utf8)
    }

    /// Build an `mvhd` box (v0) with the given timescale and duration.
    /// Layout: size(4) type(4) version(1) flags(3) creation(4) modification(4) timescale(4) duration(4) …
    /// We pad the rest with zeros to a total of 100 bytes — the parser only reads through `duration`.
    private func mvhdBoxV0(timescale: UInt32, duration: UInt32) -> [UInt8] {
        var box: [UInt8] = []
        let boxSize: UInt32 = 100
        box.append(contentsOf: be32(boxSize))
        box.append(contentsOf: fourcc("mvhd"))
        box.append(0)                                 // version = 0
        box.append(contentsOf: [0, 0, 0])              // flags
        box.append(contentsOf: be32(0))                // creation
        box.append(contentsOf: be32(0))                // modification
        box.append(contentsOf: be32(timescale))
        box.append(contentsOf: be32(duration))
        // Pad to boxSize
        while box.count < Int(boxSize) { box.append(0) }
        return box
    }

    /// Build an `mvhd` box (v1) with 8-byte duration.
    private func mvhdBoxV1(timescale: UInt32, duration: UInt64) -> [UInt8] {
        var box: [UInt8] = []
        let boxSize: UInt32 = 120
        box.append(contentsOf: be32(boxSize))
        box.append(contentsOf: fourcc("mvhd"))
        box.append(1)                                 // version = 1
        box.append(contentsOf: [0, 0, 0])              // flags
        box.append(contentsOf: be64(0))                // creation
        box.append(contentsOf: be64(0))                // modification
        box.append(contentsOf: be32(timescale))
        box.append(contentsOf: be64(duration))
        while box.count < Int(boxSize) { box.append(0) }
        return box
    }

    // MARK: - MP4 parser

    @Test("extractMP4Duration reads v0 mvhd box at the top level")
    func mp4_v0_topLevel() {
        let bytes = mvhdBoxV0(timescale: 1000, duration: 60_000)
        let data = Data(bytes)
        #expect(RecordingsViewModel.extractMP4Duration(from: data) == 60)
    }

    @Test("extractMP4Duration reads v1 mvhd box with 8-byte duration")
    func mp4_v1_topLevel() {
        // 3000s @ 1000 timescale → duration ticks = 3_000_000
        let bytes = mvhdBoxV1(timescale: 1000, duration: 3_000_000)
        let data = Data(bytes)
        #expect(RecordingsViewModel.extractMP4Duration(from: data) == 3000)
    }

    @Test("extractMP4Duration returns nil when no mvhd box is present")
    func mp4_noMvhd() {
        // Single 'free' box of size 16 with no payload.
        var bytes: [UInt8] = []
        bytes.append(contentsOf: be32(16))
        bytes.append(contentsOf: fourcc("free"))
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 8))
        #expect(RecordingsViewModel.extractMP4Duration(from: Data(bytes)) == nil)
    }

    @Test("extractMP4Duration returns nil for empty data")
    func mp4_empty() {
        #expect(RecordingsViewModel.extractMP4Duration(from: Data()) == nil)
    }

    @Test("extractMP4Duration truncates toward zero for fractional seconds")
    func mp4_truncates() {
        // 30.5s at timescale 1000 = 30_500 ticks → Int(30500 / 1000) = 30
        let bytes = mvhdBoxV0(timescale: 1000, duration: 30_500)
        #expect(RecordingsViewModel.extractMP4Duration(from: Data(bytes)) == 30)
    }

    @Test("extractMP4Duration descends into moov container to find mvhd")
    func mp4_nestedMoov() {
        let mvhd = mvhdBoxV0(timescale: 1000, duration: 45_000)
        var moov: [UInt8] = []
        // moov container: the parser descends when it sees 'moov' by advancing 8 bytes
        // so the payload must sit immediately after the 8-byte header.
        let moovSize = UInt32(8 + mvhd.count)
        moov.append(contentsOf: be32(moovSize))
        moov.append(contentsOf: fourcc("moov"))
        moov.append(contentsOf: mvhd)
        #expect(RecordingsViewModel.extractMP4Duration(from: Data(moov)) == 45)
    }

    @Test("extractMP4Duration returns nil when mvhd has zero timescale")
    func mp4_zeroTimescale() {
        let bytes = mvhdBoxV0(timescale: 0, duration: 1000)
        #expect(RecordingsViewModel.extractMP4Duration(from: Data(bytes)) == nil)
    }

    // MARK: - MKV parser

    /// Build an EBML variable-size integer (VINT) of exactly 1 byte for values < 0x80.
    /// Length marker is bit 7 (0x80), then the 7-bit value.
    private func vintOneByte(_ value: UInt8) -> UInt8 {
        precondition(value < 0x80)
        return 0x80 | value
    }

    @Test("extractMKVDuration parses a minimal Segment/Info with duration")
    func mkv_basicDuration() {
        // We build: SegmentInfo element containing TimestampScale (1_000_000 ns = 1 ms)
        // and Duration (10_000.0 ms → 10 seconds).
        //
        // Element IDs (retain length bits):
        //   Segment Info: 0x1549A966 (4 bytes)
        //   TimestampScale: 0x2AD7B1 (3 bytes)
        //   Duration: 0x4489 (2 bytes)
        //
        // VINT sizes: for data sizes under 0x80 we use 1-byte form (0x80 | size).

        var timestampScaleElement: [UInt8] = []
        timestampScaleElement.append(contentsOf: [0x2A, 0xD7, 0xB1])    // ID
        timestampScaleElement.append(vintOneByte(4))                   // size = 4 bytes
        timestampScaleElement.append(contentsOf: be32(1_000_000))      // value

        // Duration (Float64 = 8 bytes). 10_000.0 in IEEE 754 big-endian:
        let duration: Double = 10_000
        let bits = duration.bitPattern
        var durationBytes = [UInt8](repeating: 0, count: 8)
        for i in 0..<8 {
            durationBytes[i] = UInt8((bits >> UInt64((7 - i) * 8)) & 0xFF)
        }
        var durationElement: [UInt8] = []
        durationElement.append(contentsOf: [0x44, 0x89])               // ID
        durationElement.append(vintOneByte(8))                         // size = 8
        durationElement.append(contentsOf: durationBytes)

        // Segment Info container
        var infoBody: [UInt8] = []
        infoBody.append(contentsOf: timestampScaleElement)
        infoBody.append(contentsOf: durationElement)

        var infoElement: [UInt8] = []
        infoElement.append(contentsOf: [0x15, 0x49, 0xA9, 0x66])       // ID
        infoElement.append(vintOneByte(UInt8(infoBody.count)))
        infoElement.append(contentsOf: infoBody)

        let data = Data(infoElement)
        // 10_000 ms * 1_000_000 ns / 1_000_000_000 = 10 s
        #expect(RecordingsViewModel.extractMKVDuration(from: data) == 10)
    }

    @Test("extractMKVDuration returns nil when no Duration element is present")
    func mkv_missingDuration() {
        // Just a TimestampScale element at the top level (not inside a Segment Info
        // container). The parser still walks it, but finds no duration before running
        // out of data.
        var bytes: [UInt8] = []
        bytes.append(contentsOf: [0x2A, 0xD7, 0xB1])
        bytes.append(vintOneByte(4))
        bytes.append(contentsOf: be32(1_000_000))
        #expect(RecordingsViewModel.extractMKVDuration(from: Data(bytes)) == nil)
    }

    @Test("extractMKVDuration returns nil for empty data")
    func mkv_empty() {
        #expect(RecordingsViewModel.extractMKVDuration(from: Data()) == nil)
    }

    // MARK: - MPEG-TS parsePTS

    @Test("parsePTS extracts a 33-bit timestamp from 5 bytes")
    func parsePTS_basic() {
        // PTS layout:
        //   byte 0: [0010][P32 P31 P30][1]
        //   byte 1: [P29..P22]
        //   byte 2: [P21..P15][1]
        //   byte 3: [P14..P7]
        //   byte 4: [P6..P0][1]
        //
        // We craft a PTS of 0 so all the non-marker bits are 0 and marker bits are 1:
        // byte 0: 0010 0001 = 0x21
        // byte 1: 0x00
        // byte 2: 0x01
        // byte 3: 0x00
        // byte 4: 0x01
        let zeroBytes: [UInt8] = [0x21, 0x00, 0x01, 0x00, 0x01]
        #expect(RecordingsViewModel.parsePTS(from: Data(zeroBytes), at: 0) == 0)

        // Now craft PTS = 90_000 (1 second @ 90kHz)
        // 90_000 in binary: 0000 0000 0000 0000 0000 0001 0101 1111 1001 0000 (33 bits)
        // Bits laid out in the stream:
        //   top 3 (P32 P31 P30): 000
        //   next 15 (P29..P15): 0_0000_0000_0000_01
        //   next 15 (P14..P0):  0_1011_1111_0010_00 ← wait, 90000 = 0x15F90
        //
        // Easier: encode via the same math the parser uses and verify round-trip.
        let pts: UInt64 = 90_000
        let b0: UInt8 = UInt8(((pts >> 30) & 0x07) << 1) | 0x21     // top-level nibble "0010" + marker
        let b1: UInt8 = UInt8((pts >> 22) & 0xFF)
        let b2: UInt8 = UInt8((pts >> 15) & 0x7F) << 1 | 0x01
        let b3: UInt8 = UInt8((pts >> 7) & 0xFF)
        let b4: UInt8 = UInt8(pts & 0x7F) << 1 | 0x01
        let bytes = Data([b0, b1, b2, b3, b4])
        #expect(RecordingsViewModel.parsePTS(from: bytes, at: 0) == 90_000)
    }

    @Test("parsePTS honors an offset into a larger buffer")
    func parsePTS_offset() {
        let pts: UInt64 = 180_000
        let b0: UInt8 = UInt8(((pts >> 30) & 0x07) << 1) | 0x21
        let b1: UInt8 = UInt8((pts >> 22) & 0xFF)
        let b2: UInt8 = UInt8((pts >> 15) & 0x7F) << 1 | 0x01
        let b3: UInt8 = UInt8((pts >> 7) & 0xFF)
        let b4: UInt8 = UInt8(pts & 0x7F) << 1 | 0x01
        // Put the 5 PTS bytes after 3 junk bytes
        let bytes = Data([0xFF, 0xFF, 0xFF, b0, b1, b2, b3, b4])
        #expect(RecordingsViewModel.parsePTS(from: bytes, at: 3) == 180_000)
    }

    @Test("parsePTS returns nil when fewer than 5 bytes remain past the offset")
    func parsePTS_truncated() {
        let bytes = Data([0x21, 0x00, 0x01, 0x00]) // only 4 bytes
        #expect(RecordingsViewModel.parsePTS(from: bytes, at: 0) == nil)
    }

    @Test("parsePTS returns nil when offset is past the end")
    func parsePTS_pastEnd() {
        let bytes = Data([0x21, 0x00, 0x01, 0x00, 0x01])
        #expect(RecordingsViewModel.parsePTS(from: bytes, at: 1) == nil)
    }

    // MARK: - tsProbeStats

    @Test("tsProbeStats reports empty for empty buffer")
    func tsProbe_empty() {
        #expect(RecordingsViewModel.tsProbeStats(from: Data()) == "empty")
    }

    @Test("tsProbeStats reports no-sync when no 0x47 byte appears in first 188 bytes")
    func tsProbe_noSync() {
        let bytes = [UInt8](repeating: 0xFF, count: 200)
        let result = RecordingsViewModel.tsProbeStats(from: Data(bytes))
        #expect(result.hasPrefix("no-sync"))
    }

    @Test("tsProbeStats reports sync + packet count for a buffer starting with sync byte")
    func tsProbe_withSync() {
        // Two 188-byte packets, each starting with 0x47. We don't need valid PES
        // inside — the parser counts packets separately from ptsPackets.
        var bytes = [UInt8](repeating: 0x00, count: 188 * 2)
        bytes[0] = 0x47
        bytes[188] = 0x47
        let result = RecordingsViewModel.tsProbeStats(from: Data(bytes))
        #expect(result.contains("sync=0"))
        #expect(result.contains("packets=2"))
        #expect(result.contains("ptsPackets=0"))
    }

    // MARK: - estimateDurationSecondsFromPTSWindows
    //
    // Signature: (headPTSValues: [UInt64], tailPTSValues: [UInt64], expectedSeconds: Int) -> Int?
    // Scores candidates by |seconds - expectedSeconds| and only returns the best if
    // its error is within acceptableError = max(expectedSeconds/2, 1200).

    @Test("estimateDurationSecondsFromPTSWindows returns nil when either window is empty")
    func estimateDuration_emptyInputs() {
        #expect(RecordingsViewModel.estimateDurationSecondsFromPTSWindows(
            headPTSValues: [],
            tailPTSValues: [90_000],
            expectedSeconds: 3600
        ) == nil)
        #expect(RecordingsViewModel.estimateDurationSecondsFromPTSWindows(
            headPTSValues: [0],
            tailPTSValues: [],
            expectedSeconds: 3600
        ) == nil)
    }

    @Test("estimateDurationSecondsFromPTSWindows returns the delta in seconds when it matches expected")
    func estimateDuration_matchesExpected() {
        // 3600 seconds at 90kHz = 324_000_000 ticks
        let secs = RecordingsViewModel.estimateDurationSecondsFromPTSWindows(
            headPTSValues: [0],
            tailPTSValues: [324_000_000],
            expectedSeconds: 3600
        )
        #expect(secs == 3600)
    }

    @Test("estimateDurationSecondsFromPTSWindows picks the best head/tail combination")
    func estimateDuration_scoresBestCombo() {
        // expectedSeconds = 1800 (30 min). Two tail candidates: one at ~1 min, one at ~30 min.
        // The 30-min candidate is a much better match.
        let oneMinute: UInt64 = 60 * 90_000
        let thirtyMinutes: UInt64 = 1800 * 90_000
        let secs = RecordingsViewModel.estimateDurationSecondsFromPTSWindows(
            headPTSValues: [0],
            tailPTSValues: [oneMinute, thirtyMinutes],
            expectedSeconds: 1800
        )
        #expect(secs == 1800)
    }

    @Test("estimateDurationSecondsFromPTSWindows rejects negative or zero deltas")
    func estimateDuration_rejectsInvalidDelta() {
        // tailPTS <= headPTS and no viable wrap → returns nil.
        let secs = RecordingsViewModel.estimateDurationSecondsFromPTSWindows(
            headPTSValues: [1_000_000],
            tailPTSValues: [1_000_000],
            expectedSeconds: 3600
        )
        // Delta = 0 seconds which is within acceptableError but fails `seconds > 0` guard
        #expect(secs == nil)
    }
}
