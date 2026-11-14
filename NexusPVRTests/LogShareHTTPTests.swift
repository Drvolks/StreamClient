//
//  LogShareHTTPTests.swift
//  NexusPVRTests
//
//  The Apple TV's temporary log page.
//

import Testing
import Foundation
@testable import NextPVR

struct LogShareHTTPTests {
    private let body = Data("log text\n".utf8)

    private func respond(_ request: String) -> String {
        let data = LogShareHTTP.response(for: Data(request.utf8), token: "tok", fileName: "log.txt", body: body)
        return String(decoding: data, as: UTF8.self)
    }

    @Test("The token path serves the log as plain text")
    func servesLog() {
        let response = respond("GET /tok/log.txt HTTP/1.1\r\nHost: tv\r\n\r\n")
        #expect(response.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(response.contains("Content-Type: text/plain; charset=utf-8"))
        #expect(response.contains("Content-Length: \(body.count)"))
        #expect(response.hasSuffix("\r\n\r\nlog text\n"))
    }

    @Test("The bare token path serves the log too")
    func bareToken() {
        #expect(respond("GET /tok/ HTTP/1.1\r\n\r\n").hasPrefix("HTTP/1.1 200"))
    }

    @Test("Other paths are not found")
    func otherPaths() {
        #expect(respond("GET / HTTP/1.1\r\n\r\n").hasPrefix("HTTP/1.1 404"))
        #expect(respond("GET /favicon.ico HTTP/1.1\r\n\r\n").hasPrefix("HTTP/1.1 404"))
        #expect(respond("GET /wrong/log.txt HTTP/1.1\r\n\r\n").hasPrefix("HTTP/1.1 404"))
    }

    @Test("HEAD gets the headers without the body")
    func head() {
        let response = respond("HEAD /tok/log.txt HTTP/1.1\r\n\r\n")
        #expect(response.hasPrefix("HTTP/1.1 200"))
        #expect(response.hasSuffix("\r\n\r\n"))
    }

    @Test("Malformed requests get a 400")
    func malformed() {
        #expect(respond("POST /tok/log.txt HTTP/1.1\r\n\r\n").hasPrefix("HTTP/1.1 400"))
        #expect(respond("").hasPrefix("HTTP/1.1 400"))
    }

    @Test("Tokens are random and URL-safe")
    func tokens() {
        let a = LogShareHTTP.makeToken()
        let b = LogShareHTTP.makeToken()
        #expect(a != b)
        #expect(a.count >= 16)
        #expect(a.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) })
    }

    @Test("Wi-Fi/Ethernet addresses are preferred")
    func preferredAddress() {
        #expect(LocalNetworkAddress.preferred([("utun0", "10.0.0.2"), ("en1", "192.168.1.9"), ("en0", "192.168.1.5")]) == "192.168.1.5")
        #expect(LocalNetworkAddress.preferred([("utun0", "10.0.0.2"), ("en3", "192.168.1.9")]) == "192.168.1.9")
        #expect(LocalNetworkAddress.preferred([("bridge0", "10.0.0.2")]) == "10.0.0.2")
        #expect(LocalNetworkAddress.preferred([]) == nil)
    }
}
