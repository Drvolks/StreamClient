//
//  DispatcharrHLS.swift
//  DispatcherPVR
//
//  Request building and response checks for Dispatcharr's native HLS live
//  output (#193). Asking `/proxy/ts/stream/<uuid>` for `output_format=hls`
//  answers with a redirect to an opaque `/proxy/hls/<token>/index.m3u8`; the
//  token is what `DELETE /api/proxy/hls/sessions/<token>/` needs to free the
//  connection when playback ends, instead of waiting for the server to notice
//  the player stopped polling.
//

import Foundation

nonisolated enum DispatcharrHLS {
    /// Query parameter the live proxy reads the format from.
    static let formatQueryItemName = "output_format"
    /// Header carrying the token on the redirect.
    static let sessionTokenHeader = "X-Dispatcharr-Session-Token"

    /// Sets `?output_format=` on a live URL, keeping its other query items
    /// (an `output_profile`, say).
    static func applying(format: LiveStreamFormat, to url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == formatQueryItemName }
        items.append(URLQueryItem(name: formatQueryItemName, value: format.rawValue))
        components.queryItems = items
        return components.url ?? url
    }

    // MARK: - Support

    /// A GET on the session endpoint, which only accepts DELETE. A server
    /// with HLS output refuses the method (405) without touching anything;
    /// an older one has no such route and its catch-all serves the web app.
    static func probeURL(baseURL: String) -> URL? {
        sessionURL(baseURL: baseURL, token: "probe")
    }

    /// What the answer to `probeURL` says: true for a server with HLS output
    /// that lets this user stop sessions, false when it doesn't, nil when the
    /// status says nothing either way (a server error, say).
    static func supportsHLS(probeStatus status: Int) -> Bool? {
        switch status {
        case 405: return true
        // 403: the user may not stop sessions (not a Standard user), so the
        // app can't clean up after itself and doesn't offer HLS.
        case 200...299, 403, 404: return false
        default: return nil
        }
    }

    // MARK: - Sessions

    static func sessionURL(baseURL: String, token: String) -> URL? {
        guard let escaped = token.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "\(baseURL)/api/proxy/hls/sessions/\(escaped)/")
    }

    /// The token in a `/proxy/hls/<token>/index.m3u8` path or URL.
    static func token(inPlaylistLocation location: String) -> String? {
        let path = URLComponents(string: location)?.path ?? location
        let parts = path.split(separator: "/").map(String.init)
        guard let hls = parts.firstIndex(of: "hls"), hls > 0, parts[hls - 1] == "proxy",
              parts.count == hls + 3, parts[hls + 2] == "index.m3u8" else { return nil }
        return parts[hls + 1]
    }

    /// What asking for HLS led to, read from the first response without
    /// following its redirect.
    enum OpenResult: Equatable, Sendable {
        /// The HLS playlist, and the token that stops it.
        case session(token: String, location: String)
        /// Redirected somewhere else (a channel on a redirect stream
        /// profile): hand the player that location.
        case redirect(location: String)
        /// Answered with a stream rather than a redirect.
        case streaming
        case failed(status: Int)
    }

    static func openResult(status: Int, location: String?, tokenHeader: String?) -> OpenResult {
        switch status {
        case 300...399:
            guard let location, !location.isEmpty else { return .failed(status: status) }
            guard let pathToken = token(inPlaylistLocation: location) else { return .redirect(location: location) }
            // The header is the documented source; the path is the fallback.
            let header = tokenHeader?.trimmingCharacters(in: .whitespaces) ?? ""
            return .session(token: header.isEmpty ? pathToken : header, location: location)
        case 200...299:
            return .streaming
        default:
            return .failed(status: status)
        }
    }
}
