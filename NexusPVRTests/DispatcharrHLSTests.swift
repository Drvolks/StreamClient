//
//  DispatcharrHLSTests.swift
//  NexusPVRTests
//
//  Dispatcharr native HLS live output (#193): the format on live URLs,
//  detecting the server feature, reading the session token off the
//  redirect, and the format preference.
//

import Testing
import Foundation
@testable import NextPVR

struct DispatcharrHLSTests {

    private let liveURL = URL(string: "http://tv:9191/proxy/ts/stream/abc-123")!

    // MARK: - Live URLs

    @Test("The format is added as output_format, keeping an output profile")
    func appliesFormat() throws {
        let profiled = DispatcharrOutputProfile.applying(profileId: 4, to: liveURL)
        let url = DispatcharrHLS.applying(format: .hls, to: profiled)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.contains(URLQueryItem(name: "output_profile", value: "4")))
        #expect(items.contains(URLQueryItem(name: "output_format", value: "hls")))
    }

    @Test("Applying a format again replaces it")
    func replacesFormat() {
        let hls = DispatcharrHLS.applying(format: .hls, to: liveURL)
        let mpegts = DispatcharrHLS.applying(format: .mpegts, to: hls)
        #expect(mpegts.absoluteString == "http://tv:9191/proxy/ts/stream/abc-123?output_format=mpegts")
    }

    // MARK: - Detecting the feature

    @Test("The probe is a GET on the session endpoint")
    func probeURL() {
        #expect(DispatcharrHLS.probeURL(baseURL: "http://tv:9191")?.absoluteString
                == "http://tv:9191/api/proxy/hls/sessions/probe/")
    }

    @Test("Only a refused method means the server has HLS and this user can stop sessions")
    func probeStatuses() {
        #expect(DispatcharrHLS.supportsHLS(probeStatus: 405) == true)
        // An older server's catch-all route serves the web app.
        #expect(DispatcharrHLS.supportsHLS(probeStatus: 200) == false)
        #expect(DispatcharrHLS.supportsHLS(probeStatus: 404) == false)
        // Not a Standard user: can't stop a session.
        #expect(DispatcharrHLS.supportsHLS(probeStatus: 403) == false)
        #expect(DispatcharrHLS.supportsHLS(probeStatus: 502) == nil)
    }

    // MARK: - Sessions

    @Test("A session is stopped at /api/proxy/hls/sessions/<token>/")
    func sessionURL() {
        #expect(DispatcharrHLS.sessionURL(baseURL: "http://tv:9191", token: "AbC_dEf-123")?.absoluteString
                == "http://tv:9191/api/proxy/hls/sessions/AbC_dEf-123/")
    }

    @Test("The token is read from a playlist path or URL")
    func tokenFromLocation() {
        #expect(DispatcharrHLS.token(inPlaylistLocation: "/proxy/hls/AbC_dEf-123/index.m3u8") == "AbC_dEf-123")
        #expect(DispatcharrHLS.token(inPlaylistLocation: "http://tv:9191/proxy/hls/tok/index.m3u8") == "tok")
        #expect(DispatcharrHLS.token(inPlaylistLocation: "/proxy/hls/tok/7.ts") == nil)
        #expect(DispatcharrHLS.token(inPlaylistLocation: "http://provider.example/live/1.m3u8") == nil)
    }

    @Test("A redirect to the playlist opens a session, the header's token winning")
    func sessionRedirect() {
        #expect(DispatcharrHLS.openResult(status: 302, location: "/proxy/hls/fromPath/index.m3u8", tokenHeader: "fromHeader")
                == .session(token: "fromHeader", location: "/proxy/hls/fromPath/index.m3u8"))
        #expect(DispatcharrHLS.openResult(status: 302, location: "/proxy/hls/fromPath/index.m3u8", tokenHeader: nil)
                == .session(token: "fromPath", location: "/proxy/hls/fromPath/index.m3u8"))
    }

    @Test("A redirect elsewhere is passed on, a stream or an error falls back")
    func otherOutcomes() {
        #expect(DispatcharrHLS.openResult(status: 302, location: "http://provider.example/live/1.ts", tokenHeader: nil)
                == .redirect(location: "http://provider.example/live/1.ts"))
        #expect(DispatcharrHLS.openResult(status: 302, location: nil, tokenHeader: nil) == .failed(status: 302))
        #expect(DispatcharrHLS.openResult(status: 200, location: nil, tokenHeader: nil) == .streaming)
        #expect(DispatcharrHLS.openResult(status: 500, location: nil, tokenHeader: nil) == .failed(status: 500))
    }

    // MARK: - Preference

    @Test("The format defaults to MPEG-TS, including for preferences written before it existed")
    func defaultsToMPEGTS() throws {
        #expect(UserPreferences().liveStreamFormat == .mpegts)
        let json = #"{"keywords":[],"seekBackwardSeconds":10,"seekForwardSeconds":30}"#
        let prefs = try JSONDecoder().decode(UserPreferences.self, from: Data(json.utf8))
        #expect(prefs.liveStreamFormat == .mpegts)
    }

    @Test("HLS survives a round trip, and an unknown format decodes as MPEG-TS")
    func preferenceRoundTrip() throws {
        var prefs = UserPreferences()
        prefs.liveStreamFormat = .hls
        let decoded = try JSONDecoder().decode(UserPreferences.self, from: JSONEncoder().encode(prefs))
        #expect(decoded.liveStreamFormat == .hls)

        let future = #"{"keywords":[],"seekBackwardSeconds":10,"seekForwardSeconds":30,"liveStreamFormat":"cmaf"}"#
        let fromLaterVersion = try JSONDecoder().decode(UserPreferences.self, from: Data(future.utf8))
        #expect(fromLaterVersion.liveStreamFormat == .mpegts)
    }
}
