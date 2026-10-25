//
//  DispatcharrLiveFormatTests.swift
//  NexusPVRTests
//
//  The Live TV Format choices beyond MPEG-TS and HLS: fMP4 (#79), Auto and
//  Server default (#204), and reading what Dispatcharr would pick.
//

import Testing
import Foundation
@testable import NextPVR

struct DispatcharrLiveFormatTests {

    // MARK: - Resolving a choice

    @Test("A concrete format is asked for as is, whatever the network or server")
    func concreteFormats() {
        for format in [LiveStreamFormat.mpegts, .hls, .fmp4] {
            #expect(DispatcharrLiveFormat.resolve(format, onExpensiveNetwork: true, serverChoice: .hls) == format)
        }
    }

    @Test("Auto plays MPEG-TS on Wi-Fi and Ethernet, HLS on cellular and hotspot")
    func autoFollowsTheNetwork() {
        #expect(DispatcharrLiveFormat.resolve(.auto, onExpensiveNetwork: false, serverChoice: nil) == .mpegts)
        #expect(DispatcharrLiveFormat.resolve(.auto, onExpensiveNetwork: true, serverChoice: nil) == .hls)
    }

    @Test("Server default plays what Dispatcharr picks, MPEG-TS when that couldn't be read")
    func serverDefaultFollowsDispatcharr() {
        #expect(DispatcharrLiveFormat.resolve(.serverDefault, onExpensiveNetwork: true, serverChoice: .fmp4) == .fmp4)
        #expect(DispatcharrLiveFormat.resolve(.serverDefault, onExpensiveNetwork: false, serverChoice: .hls) == .hls)
        #expect(DispatcharrLiveFormat.resolve(.serverDefault, onExpensiveNetwork: false, serverChoice: nil) == .mpegts)
    }

    // MARK: - What Dispatcharr would pick

    @Test("The user's override wins over the server default")
    func overrideWins() {
        #expect(DispatcharrLiveFormat.serverChoice(userOverride: "hls", serverDefault: "fmp4") == .hls)
        #expect(DispatcharrLiveFormat.serverChoice(userOverride: nil, serverDefault: "fmp4") == .fmp4)
        #expect(DispatcharrLiveFormat.serverChoice(userOverride: "", serverDefault: "hls") == .hls)
    }

    @Test("Unknown or missing values fall back to MPEG-TS, the server's own default")
    func fallsBackToMPEGTS() {
        #expect(DispatcharrLiveFormat.serverChoice(userOverride: "cmaf", serverDefault: nil) == .mpegts)
        #expect(DispatcharrLiveFormat.serverChoice(userOverride: nil, serverDefault: nil) == .mpegts)
    }

    @Test("The proxy's aliases name the same formats")
    func aliases() {
        #expect(DispatcharrLiveFormat.format(fromServerValue: "ts") == .mpegts)
        #expect(DispatcharrLiveFormat.format(fromServerValue: "MP4") == .fmp4)
        #expect(DispatcharrLiveFormat.format(fromServerValue: " m3u8 ") == .hls)
        #expect(DispatcharrLiveFormat.format(fromServerValue: "auto") == nil, "only formats the server knows")
    }

    // MARK: - Server responses

    @Test("The server default is read from the stream_settings row; other rows are skipped")
    func decodesCoreSettings() throws {
        let json = #"""
        [{"id":1,"key":"epg_settings","name":"EPG","value":{"history_days":2}},
         {"id":2,"key":"stream_settings","name":"Stream","value":{"default_user_agent":3,"default_output_format":"hls"}},
         {"id":3,"key":"some_flag","name":"Flag","value":"on"}]
        """#
        let rows = try JSONDecoder().decode([DispatcharrCoreSetting].self, from: Data(json.utf8))
        #expect(rows.count == 3)
        #expect(rows.first { $0.key == DispatcharrCoreSetting.streamSettingsKey }?.defaultOutputFormat == "hls")
        #expect(rows.allSatisfy { $0.key == "stream_settings" || $0.defaultOutputFormat == nil })
    }

    @Test("The user's override is read from custom_properties, and may be absent")
    func decodesUserOverride() throws {
        let withOverride = #"{"id":4,"username":"jf","user_level":1,"custom_properties":{"output_format":"fmp4"}}"#
        let without = #"{"id":4,"username":"jf","user_level":1,"custom_properties":null}"#
        #expect(try JSONDecoder().decode(DispatcharrUserOutputFormat.self, from: Data(withOverride.utf8)).outputFormat == "fmp4")
        #expect(try JSONDecoder().decode(DispatcharrUserOutputFormat.self, from: Data(without.utf8)).outputFormat == nil)
    }

    // MARK: - Preference

    @Test("Each choice survives a round trip, and only fMP4 joins the concrete formats")
    func preferenceRoundTrip() throws {
        for format in LiveStreamFormat.allCases {
            var prefs = UserPreferences()
            prefs.liveStreamFormat = format
            let decoded = try JSONDecoder().decode(UserPreferences.self, from: JSONEncoder().encode(prefs))
            #expect(decoded.liveStreamFormat == format)
        }
        #expect(LiveStreamFormat.allCases.filter(\.isConcrete) == [.mpegts, .hls, .fmp4])
        #expect(LiveStreamFormat.serverDefault.rawValue == "server")
    }

    @Test("fMP4 is asked for as output_format=fmp4")
    func fmp4Query() {
        let url = URL(string: "http://tv:9191/proxy/ts/stream/abc")!
        #expect(DispatcharrHLS.applying(format: .fmp4, to: url).absoluteString
                == "http://tv:9191/proxy/ts/stream/abc?output_format=fmp4")
        // Unresolved choices are never sent as a format.
        #expect(DispatcharrHLS.applying(format: .auto, to: url) == url)
        #expect(DispatcharrHLS.applying(format: .serverDefault, to: url) == url)
    }
}
