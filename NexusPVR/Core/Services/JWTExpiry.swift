//
//  JWTExpiry.swift
//  nextpvr-apple-client
//
//  Reads the expiry (`exp`) of a Dispatcharr JWT access token, so a
//  still-valid session can be kept instead of signing in again.
//

import Foundation

nonisolated enum JWTExpiry {
    /// The token's `exp` claim, or nil when it can't be read.
    static func expirationDate(of token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = payload["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    /// True when the token is readable and stays valid for at least `margin`.
    static func isValid(_ token: String, now: Date = Date(), margin: TimeInterval = 60) -> Bool {
        guard let expiry = expirationDate(of: token) else { return false }
        return expiry.timeIntervalSince(now) > margin
    }
}
