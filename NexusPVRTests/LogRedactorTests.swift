//
//  LogRedactorTests.swift
//  NexusPVRTests
//
//  Credentials removed from shared logs.
//

import Testing
import Foundation
@testable import NextPVR

struct LogRedactorTests {
    @Test("NextPVR sid and client values are removed, other query items kept")
    func nextPVRQuery() {
        let text = LogRedactor.redact("Opening http://pvr.local:8866/live?channel=12&client=abc&sid=xyz")
        #expect(!text.contains("abc"))
        #expect(!text.contains("xyz"))
        #expect(text.contains("channel=12"))
        #expect(text.contains("sid=REDACTED"))
    }

    @Test("Dispatcharr HLS session token in the path is removed")
    func hlsToken() {
        let text = LogRedactor.redact("GET https://d.example/proxy/hls/tok123/index.m3u8 failed")
        #expect(!text.contains("tok123"))
        #expect(text.contains("/proxy/hls/REDACTED/index.m3u8"))
    }

    @Test("The HLS sessions API path is not a token")
    func hlsSessionsPath() {
        let text = LogRedactor.redact("https://d.example/api/proxy/hls/sessions/probe/")
        #expect(text == "https://d.example/api/proxy/hls/sessions/probe/")
    }

    @Test("User info and bearer tokens are removed")
    func userInfoAndBearer() {
        let text = LogRedactor.redact("http://bob:hunter2@host/x and Authorization: Bearer eyJ.abc.def")
        #expect(!text.contains("hunter2"))
        #expect(!text.contains("bob:"))
        #expect(!text.contains("eyJ.abc.def"))
        #expect(text.contains("Bearer REDACTED"))
    }

    @Test("Text without credentials is unchanged")
    func unchanged() {
        let text = "[ffmpeg] http://host:9191/proxy/ts/stream/uuid?output_format=mpegts: Stream ends prematurely"
        #expect(LogRedactor.redact(text) == text)
    }

    @Test("pathAndQuery labels a stream without its host or secrets")
    func pathLabel() {
        let url = URL(string: "http://host:8866/live?channel=3&sid=s3cret")!
        #expect(LogRedactor.pathAndQuery(of: url) == "/live?channel=3&sid=REDACTED")
    }
}
