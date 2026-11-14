//
//  LogShareHTTP.swift
//  PVR Client
//
//  The tiny HTTP exchange behind sharing a log from Apple TV.
//

import Foundation

/// Answers requests to the Apple TV's temporary log page. Only
/// `GET /<token>/<file>` gets the log; everything else is a 404, so other
/// devices on the network can't read it by guessing the port.
nonisolated enum LogShareHTTP {
    /// Request target (path) of an HTTP/1.x request, or nil when malformed.
    static func requestPath(from request: Data) -> String? {
        guard let text = String(data: request.prefix(4096), encoding: .utf8),
              let firstLine = text.components(separatedBy: "\n").first?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !firstLine.isEmpty
        else { return nil }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" || parts[0] == "HEAD" else { return nil }
        return String(parts[1])
    }

    static func isHead(_ request: Data) -> Bool {
        request.starts(with: Data("HEAD ".utf8))
    }

    /// Path the log is served at.
    static func path(token: String, fileName: String) -> String {
        "/\(token)/\(fileName)"
    }

    /// Full response for `request`.
    static func response(for request: Data, token: String, fileName: String, body: Data) -> Data {
        let expected = path(token: token, fileName: fileName)
        guard let target = requestPath(from: request) else {
            return makeResponse(status: "400 Bad Request", body: Data("Bad request\n".utf8))
        }
        let pathOnly = target.split(separator: "?", maxSplits: 1).first.map(String.init) ?? target
        guard pathOnly == expected || pathOnly == "/\(token)" || pathOnly == "/\(token)/" else {
            return makeResponse(status: "404 Not Found", body: Data("Not found\n".utf8))
        }
        return makeResponse(
            status: "200 OK",
            body: body,
            extraHeaders: ["Content-Disposition": "inline; filename=\"\(fileName)\""],
            omitBody: isHead(request)
        )
    }

    static func makeResponse(
        status: String,
        body: Data,
        extraHeaders: [String: String] = [:],
        omitBody: Bool = false
    ) -> Data {
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: text/plain; charset=utf-8\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "Connection: close\r\n"
        for (name, value) in extraHeaders.sorted(by: { $0.key < $1.key }) {
            head += "\(name): \(value)\r\n"
        }
        head += "\r\n"
        var data = Data(head.utf8)
        if !omitBody { data.append(body) }
        return data
    }

    /// Random URL-safe token for the log path.
    static func makeToken() -> String {
        (0..<4).map { _ in String(UInt32.random(in: .min ... .max), radix: 36) }.joined()
    }
}
