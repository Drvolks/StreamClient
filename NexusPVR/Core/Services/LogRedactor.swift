//
//  LogRedactor.swift
//  PVR Client
//
//  Strips credentials from text that goes into a shared log.
//

import Foundation

/// Removes credentials from log text before it is stored in a playback
/// session or shared: sensitive query values (NextPVR's `sid`/`client`,
/// tokens, keys, passwords), URL user info, Dispatcharr's HLS session token
/// in `/proxy/hls/<token>/`, and bearer tokens.
nonisolated enum LogRedactor {
    static let placeholder = "REDACTED"

    static let sensitiveQueryNames: Set<String> = [
        "sid", "client", "token", "access_token", "refresh_token", "session_token",
        "key", "api_key", "apikey", "password", "pass", "pwd", "pin",
        "auth", "jwt", "signature", "sig", "secret",
    ]

    private static let urlPattern = try! NSRegularExpression(
        pattern: #"https?://[^\s'"<>]+"#,
        options: [.caseInsensitive]
    )
    private static let bearerPattern = try! NSRegularExpression(
        pattern: #"(Bearer\s+)[A-Za-z0-9._~+/=-]+"#,
        options: [.caseInsensitive]
    )

    /// `text` with every URL in it redacted, and bearer tokens removed.
    static func redact(_ text: String) -> String {
        var result = text
        let ns = result as NSString
        let matches = urlPattern.matches(in: result, range: NSRange(location: 0, length: ns.length))
        for match in matches.reversed() {
            let original = ns.substring(with: match.range)
            let redacted = redactURLString(original)
            guard redacted != original, let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: redacted)
        }
        let full = NSRange(result.startIndex..., in: result)
        return bearerPattern.stringByReplacingMatches(
            in: result, range: full, withTemplate: "$1\(placeholder)"
        )
    }

    /// The URL as a string with its credentials replaced.
    static func redact(url: URL) -> String {
        redactURLString(url.absoluteString)
    }

    /// Path and query of `url`, redacted: a short label for a stream.
    static func pathAndQuery(of url: URL) -> String {
        let redacted = redactURLString(url.absoluteString)
        guard let components = URLComponents(string: redacted) else { return url.path }
        var label = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        if let query = components.percentEncodedQuery, !query.isEmpty {
            label += "?\(query)"
        }
        return label
    }

    private static func redactURLString(_ string: String) -> String {
        guard var components = URLComponents(string: string) else { return string }
        var changed = false
        if components.user != nil || components.password != nil {
            components.user = nil
            components.password = nil
            changed = true
        }
        if let items = components.percentEncodedQueryItems, !items.isEmpty {
            let redacted = items.map { item -> URLQueryItem in
                guard sensitiveQueryNames.contains(item.name.lowercased()),
                      let value = item.value, !value.isEmpty else { return item }
                changed = true
                return URLQueryItem(name: item.name, value: placeholder)
            }
            components.percentEncodedQueryItems = redacted
        }
        let segments = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
        if let hls = segments.firstIndex(of: "hls"), hls > 0, segments[hls - 1] == "proxy",
           hls + 1 < segments.count, !segments[hls + 1].isEmpty, segments[hls + 1] != "sessions" {
            var rebuilt = segments.map(String.init)
            rebuilt[hls + 1] = placeholder
            components.percentEncodedPath = rebuilt.joined(separator: "/")
            changed = true
        }
        guard changed else { return string }
        return components.string ?? string
    }
}
