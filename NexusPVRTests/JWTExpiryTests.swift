//
//  JWTExpiryTests.swift
//  NexusPVRTests
//
//  Reading a JWT's expiry, used to keep a Dispatcharr session on foreground.
//

import Foundation
import Testing
@testable import NextPVR

struct JWTExpiryTests {

    /// An unsigned token with the given payload (base64url, no padding).
    private func token(payload: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: payload)
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "eyJhbGciOiJIUzI1NiJ9.\(encoded).signature"
    }

    @Test("Reads the exp claim")
    func readsExpiry() {
        let exp = 1_800_000_000.0
        #expect(JWTExpiry.expirationDate(of: token(payload: ["exp": exp, "user_id": 1])) == Date(timeIntervalSince1970: exp))
    }

    @Test("Unreadable tokens have no expiry")
    func unreadable() {
        #expect(JWTExpiry.expirationDate(of: "not-a-jwt") == nil)
        #expect(JWTExpiry.expirationDate(of: "a.b.c") == nil)
        #expect(JWTExpiry.expirationDate(of: token(payload: ["user_id": 1])) == nil)
    }

    @Test("Valid only while more than the margin remains")
    func validity() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(JWTExpiry.isValid(token(payload: ["exp": 1_000_000 + 600.0]), now: now))
        #expect(!JWTExpiry.isValid(token(payload: ["exp": 1_000_000 + 30.0]), now: now))
        #expect(!JWTExpiry.isValid(token(payload: ["exp": 1_000_000 - 10.0]), now: now))
        #expect(!JWTExpiry.isValid("garbage", now: now))
    }
}
