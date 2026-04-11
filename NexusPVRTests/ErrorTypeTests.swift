//
//  ErrorTypeTests.swift
//  NexusPVRTests
//
//  Tests for NextPVRError and PVRClientError LocalizedError conformance.
//

import Testing
import Foundation
@testable import NextPVR

struct ErrorTypeTests {

    // MARK: - NextPVRError

    @Test("NextPVRError notConfigured has expected message")
    func nextNotConfigured() {
        #expect(NextPVRError.notConfigured.errorDescription == "Server not configured")
    }

    @Test("NextPVRError authenticationFailed mentions PIN")
    func nextAuthFailed() {
        let desc = NextPVRError.authenticationFailed.errorDescription ?? ""
        #expect(desc.contains("PIN"))
    }

    @Test("NextPVRError sessionExpired mentions reconnect")
    func nextSessionExpired() {
        let desc = NextPVRError.sessionExpired.errorDescription ?? ""
        #expect(desc.lowercased().contains("reconnect"))
    }

    @Test("NextPVRError invalidResponse has expected message")
    func nextInvalidResponse() {
        #expect(NextPVRError.invalidResponse.errorDescription == "Invalid response from server")
    }

    @Test("NextPVRError apiError returns the wrapped message verbatim")
    func nextApiError() {
        #expect(NextPVRError.apiError("custom failure").errorDescription == "custom failure")
    }

    @Test("NextPVRError networkError with DecodingError suggests URL is incorrect")
    func nextDecodingErrorHint() {
        struct DummyKey: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init?(intValue: Int) { nil }
            init?(stringValue: String) { self.stringValue = stringValue }
        }
        let decodingError = DecodingError.keyNotFound(
            DummyKey(stringValue: "x")!,
            DecodingError.Context(codingPath: [], debugDescription: "missing")
        )
        let err = NextPVRError.networkError(decodingError)
        let desc = err.errorDescription ?? ""
        #expect(desc.lowercased().contains("server url"))
    }

    @Test("NextPVRError networkError with plain URLError includes the underlying message")
    func nextGenericNetworkError() {
        let underlying = URLError(.notConnectedToInternet)
        let err = NextPVRError.networkError(underlying)
        let desc = err.errorDescription ?? ""
        #expect(desc.hasPrefix("Network error:"))
    }

    @Test("NextPVRError localizedDescription is never empty")
    func nextLocalizedNonEmpty() {
        let cases: [NextPVRError] = [
            .notConfigured,
            .authenticationFailed,
            .sessionExpired,
            .invalidResponse,
            .apiError("x"),
            .networkError(URLError(.badURL))
        ]
        for c in cases {
            #expect((c.errorDescription ?? "").isEmpty == false)
        }
    }

    // MARK: - PVRClientError

    @Test("PVRClientError notConfigured has expected message")
    func clientNotConfigured() {
        #expect(PVRClientError.notConfigured.errorDescription == "Server not configured")
    }

    @Test("PVRClientError authenticationFailed mentions credentials")
    func clientAuthFailed() {
        let desc = PVRClientError.authenticationFailed.errorDescription ?? ""
        #expect(desc.lowercased().contains("credentials"))
    }

    @Test("PVRClientError apiError returns wrapped message")
    func clientApiError() {
        #expect(PVRClientError.apiError("boom").errorDescription == "boom")
    }

    @Test("PVRClientError invalidResponse has expected message")
    func clientInvalidResponse() {
        #expect(PVRClientError.invalidResponse.errorDescription == "Invalid response from server")
    }

    @Test("PVRClientError sessionExpired mentions reconnect")
    func clientSessionExpired() {
        let desc = PVRClientError.sessionExpired.errorDescription ?? ""
        #expect(desc.lowercased().contains("reconnect"))
    }

    @Test("PVRClientError networkError wraps underlying localizedDescription")
    func clientNetworkError() {
        let url = URLError(.timedOut)
        let err = PVRClientError.networkError(url)
        let desc = err.errorDescription ?? ""
        #expect(desc.hasPrefix("Network error:"))
    }
}
