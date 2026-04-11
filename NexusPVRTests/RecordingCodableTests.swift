//
//  RecordingCodableTests.swift
//  NexusPVRTests
//
//  Additional tests for Recording's custom Decodable paths and
//  uncovered edge cases in the main coverage report (~48% → higher).
//

import Testing
import Foundation
@testable import NextPVR

struct RecordingCodableTests {

    // MARK: - recurring as Int or Bool

    @Test("Decodes recurring when provided as an integer")
    func recurring_asInt() throws {
        let json = #"{"id": 1, "name": "X", "recurring": 42}"#
        let r = try JSONDecoder().decode(Recording.self, from: Data(json.utf8))
        #expect(r.recurring == 42)
    }

    @Test("Decodes recurring: true as 1")
    func recurring_asBoolTrue() throws {
        let json = #"{"id": 1, "name": "X", "recurring": true}"#
        let r = try JSONDecoder().decode(Recording.self, from: Data(json.utf8))
        #expect(r.recurring == 1)
    }

    @Test("Decodes recurring: false as 0")
    func recurring_asBoolFalse() throws {
        let json = #"{"id": 1, "name": "X", "recurring": false}"#
        let r = try JSONDecoder().decode(Recording.self, from: Data(json.utf8))
        #expect(r.recurring == 0)
    }

    @Test("Decodes missing recurring field as nil")
    func recurring_missing() throws {
        let json = #"{"id": 1, "name": "X"}"#
        let r = try JSONDecoder().decode(Recording.self, from: Data(json.utf8))
        #expect(r.recurring == nil)
    }

    // MARK: - seriesBannerURL fallback chain

    @Test("Decodes explicit series_banner_url field")
    func bannerURL_explicit() throws {
        let json = #"{"id": 1, "name": "X", "series_banner_url": "http://banner"}"#
        let r = try JSONDecoder().decode(Recording.self, from: Data(json.utf8))
        #expect(r.seriesBannerURL == "http://banner")
    }

    @Test("Falls back to 'banner' dynamic key when series_banner_url is missing")
    func bannerURL_dynamicBanner() throws {
        let json = #"{"id": 1, "name": "X", "banner": "http://b"}"#
        let r = try JSONDecoder().decode(Recording.self, from: Data(json.utf8))
        #expect(r.seriesBannerURL == "http://b")
    }

    @Test("Falls back to 'poster_url' when neither explicit nor banner present")
    func bannerURL_posterUrl() throws {
        let json = #"{"id": 1, "name": "X", "poster_url": "http://p"}"#
        let r = try JSONDecoder().decode(Recording.self, from: Data(json.utf8))
        #expect(r.seriesBannerURL == "http://p")
    }

    @Test("Falls back to 'thumbnail' when higher-priority keys are missing")
    func bannerURL_thumbnail() throws {
        let json = #"{"id": 1, "name": "X", "thumbnail": "http://t"}"#
        let r = try JSONDecoder().decode(Recording.self, from: Data(json.utf8))
        #expect(r.seriesBannerURL == "http://t")
    }

    @Test("Empty seriesBannerURL string is skipped in the fallback chain")
    func bannerURL_skipsEmpty() throws {
        let json = #"{"id": 1, "name": "X", "series_banner_url": "", "banner": "http://b"}"#
        let r = try JSONDecoder().decode(Recording.self, from: Data(json.utf8))
        #expect(r.seriesBannerURL == "http://b")
    }

    @Test("No banner/image keys → nil")
    func bannerURL_missing() throws {
        let json = #"{"id": 1, "name": "X"}"#
        let r = try JSONDecoder().decode(Recording.self, from: Data(json.utf8))
        #expect(r.seriesBannerURL == nil)
    }

    // MARK: - Full decode with all fields

    @Test("Decodes a fully-populated recording including optional fields")
    func fullDecode() throws {
        let json = """
        {
            "id": 100,
            "name": "Show \u{1D3A}\u{1D49}\u{02B7}",
            "subtitle": "Pilot",
            "desc": "Description",
            "startTime": 1700000000,
            "duration": 3600,
            "channel": "ABC",
            "channelId": 5,
            "status": "Ready",
            "file": "/tmp/x.ts",
            "recurring": 7,
            "recurringParent": 1,
            "epgEventId": 42,
            "size": 1234567890,
            "quality": "HD",
            "genres": ["Drama", "Sport"],
            "playbackPosition": 600,
            "prePadding": 5,
            "postPadding": 10,
            "season": 1,
            "episode": 2,
            "series_banner_url": "http://banner"
        }
        """
        let r = try JSONDecoder().decode(Recording.self, from: Data(json.utf8))
        #expect(r.id == 100)
        #expect(r.isNew)
        #expect(r.cleanName == "Show")
        #expect(r.subtitle == "Pilot")
        #expect(r.startTime == 1_700_000_000)
        #expect(r.duration == 3600)
        #expect(r.channel == "ABC")
        #expect(r.channelId == 5)
        #expect(r.recordingStatus == .ready)
        #expect(r.file == "/tmp/x.ts")
        #expect(r.recurring == 7)
        #expect(r.recurringParent == 1)
        #expect(r.epgEventId == 42)
        #expect(r.size == 1_234_567_890)
        #expect(r.quality == "HD")
        #expect(r.genres == ["Drama", "Sport"])
        #expect(r.playbackPosition == 600)
        #expect(r.prePadding == 5)
        #expect(r.postPadding == 10)
        #expect(r.season == 1)
        #expect(r.episode == 2)
        #expect(r.seriesBannerURL == "http://banner")
        #expect(r.totalRecordingDuration == 3600 + 300 + 600)
        #expect(r.recordingStartTime == 1_700_000_000 - 300)
    }

    // MARK: - Preview fixtures

    @Test("Recording.preview returns a completed HD recording")
    func previewFixture() {
        let preview = Recording.preview
        #expect(preview.name == "Sample Recording")
        #expect(preview.recordingStatus == .ready)
        #expect(preview.channel == "ABC")
        #expect(preview.duration == 3600)
        #expect(preview.size ?? 0 > 0)
    }

    @Test("Recording.scheduledPreview returns a pending recurring recording")
    func scheduledPreviewFixture() {
        let preview = Recording.scheduledPreview
        #expect(preview.name == "Upcoming Show")
        #expect(preview.recordingStatus == .pending)
        #expect(preview.recurring == 100)
        #expect(preview.size == nil)
    }

    @Test("Minimum-field decode uses defaults for all optionals")
    func minimalDecode() throws {
        let json = #"{"id": 1, "name": "X"}"#
        let r = try JSONDecoder().decode(Recording.self, from: Data(json.utf8))
        #expect(r.id == 1)
        #expect(r.name == "X")
        #expect(r.subtitle == nil)
        #expect(r.desc == nil)
        #expect(r.startTime == nil)
        #expect(r.duration == nil)
        #expect(r.channel == nil)
        #expect(r.channelId == nil)
        #expect(r.status == nil)
        #expect(r.recordingStatus == .pending)
        #expect(r.size == nil)
        #expect(r.playbackPosition == nil)
        #expect(r.prePadding == nil)
        #expect(r.postPadding == nil)
        #expect(r.isWatched == false)
        #expect(r.hasResumePosition == false)
        #expect(r.totalRecordingDuration == nil)
        #expect(r.recordingStartTime == nil)
        #expect(r.fileSizeFormatted == nil)
    }
}
