//
//  OutputProfileTests.swift
//  NexusPVRTests
//
//  Tests for Dispatcharr Output Profile selection on live TV (#161):
//  decoding, URL construction, Original behaviour, fallback, persistence.
//

import Testing
import Foundation
@testable import NextPVR

struct OutputProfileTests {

    // MARK: - Decoding

    @Test("Decodes the fields Dispatcharr's serializer sends")
    func decodesProfile() throws {
        let json = #"{"id":3,"name":"Apple TV","command":"ffmpeg","parameters":"-c:v copy","is_active":true,"locked":false}"#
        let profile = try JSONDecoder().decode(DispatcharrOutputProfile.self, from: Data(json.utf8))
        #expect(profile.id == 3)
        #expect(profile.name == "Apple TV")
        #expect(profile.isActive)
    }

    @Test("Inactive profiles decode as inactive")
    func decodesInactive() throws {
        let json = #"{"id":7,"name":"Retired","is_active":false}"#
        let profile = try JSONDecoder().decode(DispatcharrOutputProfile.self, from: Data(json.utf8))
        #expect(!profile.isActive)
    }

    @Test("Missing name and is_active fall back sensibly")
    func decodesSparsePayload() throws {
        let profile = try JSONDecoder().decode(DispatcharrOutputProfile.self, from: Data(#"{"id":9}"#.utf8))
        #expect(profile.name == "Profile #9")
        #expect(profile.isActive)
    }

    @Test("List decodes from a plain array and from a paginated envelope")
    func decodesListShapes() throws {
        let array = #"[{"id":1,"name":"A","is_active":true},{"id":2,"name":"B","is_active":false}]"#
        let plain = try JSONDecoder().decode(DispatcharrListResponse<DispatcharrOutputProfile>.self, from: Data(array.utf8))
        #expect(plain.allItems.map(\.id) == [1, 2])

        let envelope = #"{"count":1,"next":null,"results":[{"id":5,"name":"C","is_active":true}]}"#
        let paged = try JSONDecoder().decode(DispatcharrListResponse<DispatcharrOutputProfile>.self, from: Data(envelope.utf8))
        #expect(paged.allItems.map(\.id) == [5])
        #expect(paged.count == 1)
    }

    // MARK: - URL construction

    @Test("Original leaves both live URL forms untouched")
    func originalOmitsParameter() throws {
        let proxy = try #require(URL(string: "http://server:9191/proxy/ts/stream/abc-uuid"))
        let xc = try #require(URL(string: "http://server:9191/live/user/p%40ss/42"))
        #expect(DispatcharrOutputProfile.applying(profileId: nil, to: proxy) == proxy)
        #expect(DispatcharrOutputProfile.applying(profileId: nil, to: xc) == xc)
    }

    @Test("A profile is appended to the proxy UUID form")
    func appendsToProxyURL() throws {
        let proxy = try #require(URL(string: "http://server:9191/proxy/ts/stream/abc-uuid"))
        let url = DispatcharrOutputProfile.applying(profileId: 3, to: proxy)
        #expect(url.absoluteString == "http://server:9191/proxy/ts/stream/abc-uuid?output_profile=3")
    }

    @Test("A profile is appended to the XC credential form, keeping the encoded password")
    func appendsToXCURL() throws {
        let xc = try #require(URL(string: "http://server:9191/live/user/p%40ss/42"))
        let url = DispatcharrOutputProfile.applying(profileId: 3, to: xc)
        #expect(url.absoluteString == "http://server:9191/live/user/p%40ss/42?output_profile=3")
    }

    @Test("Existing query items are preserved and a stale output_profile is replaced")
    func preservesExistingQuery() throws {
        let base = try #require(URL(string: "http://server/proxy/ts/stream/u?session_id=s1&output_profile=1"))
        let url = DispatcharrOutputProfile.applying(profileId: 3, to: base)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = components.queryItems ?? []
        #expect(items.first(where: { $0.name == "session_id" })?.value == "s1")
        #expect(items.filter { $0.name == "output_profile" }.map(\.value) == ["3"])
    }

    // MARK: - Resolution / fallback

    private let active = DispatcharrOutputProfile(id: 3, name: "Apple TV", isActive: true)
    private let inactive = DispatcharrOutputProfile(id: 7, name: "Retired", isActive: false)

    @Test("No selection resolves to Original with no notice")
    func nilSelectionIsOriginal() {
        let resolution = DispatcharrOutputProfile.resolve(selectedId: nil, available: [active])
        #expect(resolution == .original)
        #expect(resolution.profileId == nil)
        #expect(resolution.notice == nil)
    }

    @Test("A selected active profile is sent")
    func activeSelectionIsSent() {
        let resolution = DispatcharrOutputProfile.resolve(selectedId: 3, available: [active, inactive])
        #expect(resolution == .profile(active))
        #expect(resolution.profileId == 3)
        #expect(resolution.notice == nil)
    }

    @Test("A deleted or inactive profile falls back to Original with a visible notice")
    func missingSelectionFallsBack() {
        for selected in [7, 99] {
            let resolution = DispatcharrOutputProfile.resolve(selectedId: selected, available: [active, inactive])
            #expect(resolution.profileId == nil)
            let notice = resolution.notice ?? ""
            #expect(notice.contains("#\(selected)"))
            #expect(notice.contains("original"))
        }
    }

    @Test("An unreadable profile list falls back to Original and says so")
    func unknownServerListFallsBack() {
        let resolution = DispatcharrOutputProfile.resolve(selectedId: 3, available: nil)
        #expect(resolution.profileId == nil)
        #expect(resolution.notice?.contains("Couldn't read") == true)
    }

    // MARK: - Persistence

    @Test("Preferences default to Original")
    func defaultsToOriginal() {
        #expect(UserPreferences().outputProfileId == nil)
    }

    @Test("Preferences written before the setting existed decode to Original")
    func legacyPreferencesDecodeToOriginal() throws {
        let json = #"{"keywords":[],"seekBackwardSeconds":10,"seekForwardSeconds":30}"#
        let prefs = try JSONDecoder().decode(UserPreferences.self, from: Data(json.utf8))
        #expect(prefs.outputProfileId == nil)
    }

    @Test("Selection survives an encode/decode round trip")
    func roundTrips() throws {
        var prefs = UserPreferences()
        prefs.outputProfileId = 3
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(UserPreferences.self, from: data)
        #expect(decoded.outputProfileId == 3)
    }

    @Test("Original is encoded as an absent key, not null")
    func originalEncodesAsAbsent() throws {
        let data = try JSONEncoder().encode(UserPreferences())
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["outputProfileId"] == nil)
    }

    // MARK: - NextPVR unaffected

    @Test("The NextPVR stream quality setting is untouched by the output profile field")
    func nextPVRQualityIndependent() throws {
        var prefs = UserPreferences()
        prefs.outputProfileId = 3
        #expect(prefs.streamQuality == .original)
        let decoded = try JSONDecoder().decode(UserPreferences.self, from: JSONEncoder().encode(prefs))
        #expect(decoded.streamQuality == .original)
        #expect(decoded.outputProfileId == 3)
    }
}
