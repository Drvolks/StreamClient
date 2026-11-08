//
//  RecordingProbeRedirectTests.swift
//  NexusPVRTests
//
//  The duration probe follows Dispatcharr's /file/ → /hls/index.m3u8
//  redirect for a recording whose MKV was never written: the auth headers
//  must survive the hop (only to the same server), and the playlist's
//  length counts as the recording's duration once it is finished.
//

import Testing
import Foundation
@testable import NextPVR

struct RecordingProbeRedirectTests {

    private let auth = ["Authorization": "Bearer abc"]

    private func redirected(from original: String, to target: String) -> URLRequest {
        SameServerAuthRedirectDelegate.redirect(
            URLRequest(url: URL(string: target)!),
            from: URL(string: original),
            headers: auth
        )
    }

    // MARK: - Redirect headers

    @Test("Keeps the auth header on a redirect to the same server")
    func sameServerKeepsAuth() {
        let request = redirected(
            from: "http://pvr.local:9191/api/channels/recordings/194/file/",
            to: "http://pvr.local:9191/api/channels/recordings/194/hls/index.m3u8"
        )
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
    }

    @Test("Host comparison ignores case")
    func hostCaseInsensitive() {
        let request = redirected(from: "http://PVR.local/a", to: "http://pvr.local/b")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
    }

    @Test("Never sends the auth header to another host", arguments: [
        "http://evil.example/b",
        "http://pvr.local:8080/b",
        "https://pvr.local/b",
    ])
    func otherServerGetsNoAuth(target: String) {
        let request = redirected(from: "http://pvr.local/a", to: target)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("Leaves a header the redirect already carries alone")
    func keepsExistingHeader() {
        var target = URLRequest(url: URL(string: "http://pvr.local/b")!)
        target.setValue("Bearer other", forHTTPHeaderField: "Authorization")
        let request = SameServerAuthRedirectDelegate.redirect(
            target, from: URL(string: "http://pvr.local/a"), headers: auth
        )
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer other")
    }

    // MARK: - Playlist duration

    private let finished = """
    #EXTM3U
    #EXT-X-PLAYLIST-TYPE:EVENT
    #EXTINF:6.4,
    seg_00000.ts
    #EXTINF:3.2,
    seg_00001.ts
    #EXTINF:0.62,
    seg_00002.ts
    #EXT-X-ENDLIST
    """

    @Test("Recognises an HLS playlist, not MKV data")
    func detectsPlaylist() {
        #expect(RecordingsViewModel.isHLSPlaylist(Data(finished.utf8)))
        #expect(!RecordingsViewModel.isHLSPlaylist(Data([0x1A, 0x45, 0xDF, 0xA3])))
        #expect(!RecordingsViewModel.isHLSPlaylist(Data()))
    }

    @Test("A finished playlist's length is the sum of its segments")
    func finishedPlaylistDuration() {
        #expect(RecordingsViewModel.completedHLSPlaylistDuration(from: Data(finished.utf8)) == 10)
    }

    @Test("A playlist that is still growing has no final length")
    func growingPlaylist() {
        let growing = finished.replacingOccurrences(of: "#EXT-X-ENDLIST", with: "")
        #expect(RecordingsViewModel.completedHLSPlaylistDuration(from: Data(growing.utf8)) == nil)
    }

    @Test("A finished playlist with no segments has no length")
    func emptyPlaylist() {
        let empty = "#EXTM3U\n#EXT-X-ENDLIST\n"
        #expect(RecordingsViewModel.completedHLSPlaylistDuration(from: Data(empty.utf8)) == nil)
    }
}
