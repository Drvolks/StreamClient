//
//  StreamQualityTests.swift
//  NexusPVRTests
//
//  Tests for the user-selectable live TV transcoding profile.
//

import Testing
import Foundation
@testable import NextPVR

struct StreamQualityTests {

    // MARK: - Profile mapping

    @Test("Original never transcodes")
    func originalIsDirect() {
        #expect(StreamQuality.original.isTranscoded == false)
        #expect(StreamQuality.original.profileName == nil)
    }

    @Test("Every other quality maps to a NextPVR profile name")
    func qualitiesMapToProfiles() {
        #expect(StreamQuality.p1080.profileName == "1080p")
        #expect(StreamQuality.p720.profileName == "720p")
        #expect(StreamQuality.p480.profileName == "480p")
        #expect(StreamQuality.p144.profileName == "144p")

        for quality in StreamQuality.allCases where quality != .original {
            #expect(quality.isTranscoded)
            #expect(quality.profileName == "\(quality.rawValue)p")
        }
    }

    @Test("Options match the resolutions NextPVR servers ship profiles for")
    func optionsMatchServerProfiles() {
        #expect(StreamQuality.allCases.map(\.rawValue) == [
            "Original", "1080", "720", "576", "504", "480", "360", "240", "144"
        ])
    }

    @Test("Every option has a label and a summary")
    func optionsAreLabelled() {
        for quality in StreamQuality.allCases {
            #expect(!quality.label.isEmpty)
            #expect(!quality.summary.isEmpty)
            #expect(!quality.icon.isEmpty)
        }
        #expect(StreamQuality.original.label == "Original")
        #expect(StreamQuality.p720.label == "720p")
    }

    // MARK: - Persistence

    @Test("Preferences default to the direct stream")
    func defaultsToOriginal() {
        #expect(UserPreferences().streamQuality == .original)
    }

    @Test("Preferences written before the setting existed decode to Original")
    func legacyPreferencesDecodeToOriginal() throws {
        // A blob from an older build: no streamQuality key at all. Decoding it
        // to anything else would silently start transcoding on upgrade.
        let json = #"{"keywords":[],"seekBackwardSeconds":10,"seekForwardSeconds":30}"#
        let prefs = try JSONDecoder().decode(UserPreferences.self, from: Data(json.utf8))
        #expect(prefs.streamQuality == .original)
    }

    @Test("Quality survives an encode/decode round trip")
    func roundTrips() throws {
        var prefs = UserPreferences()
        prefs.streamQuality = .p480
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(UserPreferences.self, from: data)
        #expect(decoded.streamQuality == .p480)
    }

    // MARK: - Transcode status parsing

    @Test("A ready transcode parses")
    func parsesReadyStatus() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rsp stat="ok">
          <percentage>100</percentage>
          <final>true</final>
        </rsp>
        """
        let progress = NextPVRClient.parseTranscodeStatus(Data(xml.utf8))
        #expect(progress?.percentage == 100)
        #expect(progress?.isReady == true)
        #expect(progress?.hasFailed == false)
    }

    @Test("A transcode still starting up is neither ready nor failed")
    func parsesInProgressStatus() {
        let xml = "<rsp stat=\"ok\"><percentage>40</percentage><final>false</final></rsp>"
        let progress = NextPVRClient.parseTranscodeStatus(Data(xml.utf8))
        #expect(progress?.isReady == false)
        #expect(progress?.hasFailed == false)
    }

    @Test("A final status short of 100 is a failed transcode")
    func parsesStalledStatus() {
        // The server gave up — fall back to the direct stream rather than
        // waiting out the full timeout.
        let xml = "<rsp stat=\"ok\"><percentage>30</percentage><final>true</final></rsp>"
        let progress = NextPVRClient.parseTranscodeStatus(Data(xml.utf8))
        #expect(progress?.hasFailed == true)
        #expect(progress?.isReady == false)
    }

    @Test("Missing final element defaults to not final")
    func missingFinalDefaultsToFalse() {
        let progress = NextPVRClient.parseTranscodeStatus(Data("<rsp><percentage>10</percentage></rsp>".utf8))
        #expect(progress?.isFinal == false)
    }

    @Test("A document without a percentage yields no progress")
    func parsesMissingPercentage() {
        #expect(NextPVRClient.parseTranscodeStatus(Data("<rsp stat=\"ok\"/>".utf8)) == nil)
    }

    @Test("Malformed XML yields no progress rather than throwing")
    func parsesMalformedDocument() {
        #expect(NextPVRClient.parseTranscodeStatus(Data("not xml at all".utf8)) == nil)
    }

    // MARK: - Refusals

    @Test("A hardware-encoder failure is read as a refusal, not as progress")
    func detectsEncoderFailure() {
        // Verbatim from a NextPVR server whose VAAPI render node was
        // unreadable: ffmpeg exited immediately and the server reported this
        // at HTTP 200. Treating it as anything but a failure leaves the user
        // watching the full-bitrate stream with no indication why.
        let xml = """
        <rsp stat="fail">
          <err code="11" msg="Failed to start requested stream" />
        </rsp>
        """
        let failure = NextPVRClient.transcodeFailure(Data(xml.utf8))
        #expect(failure == "Failed to start requested stream (err 11)")
        // It carries no <percentage>, so it must not read as progress either.
        #expect(NextPVRClient.parseTranscodeStatus(Data(xml.utf8)) == nil)
    }

    @Test("An accepted transcode is not reported as a refusal")
    func acceptedTranscodeIsNotAFailure() {
        #expect(NextPVRClient.transcodeFailure(Data(#"<rsp stat="ok"/>"#.utf8)) == nil)
        let status = #"<rsp stat="ok"><percentage>100</percentage><final>true</final></rsp>"#
        #expect(NextPVRClient.transcodeFailure(Data(status.utf8)) == nil)
    }

    @Test("A refusal without a code still yields the server's message")
    func refusalWithoutCode() {
        #expect(NextPVRClient.transcodeFailure(Data(#"<rsp stat="fail"><err msg="Unknown profile"/></rsp>"#.utf8))
                == "Unknown profile")
    }

    @Test("Malformed XML is not mistaken for a refusal")
    func malformedIsNotARefusal() {
        #expect(NextPVRClient.transcodeFailure(Data("not xml".utf8)) == nil)
    }

    // MARK: - Demo mode

    @MainActor
    @Test("Demo mode ignores the transcode setting")
    func demoModeIsUnaffected() async throws {
        let client = NextPVRClient(config: ServerConfig(host: "demo", pin: "", useHTTPS: false))
        client.streamQualityOverride = .p360
        try await client.authenticate()
        let channels = try await client.getChannels()
        let url = try await client.liveStreamURL(channelId: try #require(channels.first).id)
        #expect(!url.absoluteString.contains("transcode"))
        #expect(!client.hasActiveLiveStream)
        // Nothing was attempted, so nothing to warn about — the player must not
        // show a fallback banner over a stream that is playing as asked.
        #expect(client.streamQualityNotice == nil)
    }

    @MainActor
    @Test("The fallback notice is cleared when a new stream starts")
    func noticeIsClearedPerStream() async throws {
        let client = NextPVRClient(config: ServerConfig(host: "demo", pin: "", useHTTPS: false))
        try await client.authenticate()
        let channels = try await client.getChannels()
        _ = try await client.liveStreamURL(channelId: try #require(channels.first).id)
        #expect(client.streamQualityNotice == nil)
        client.clearStreamQualityNotice()
        #expect(client.streamQualityNotice == nil)
    }
}
