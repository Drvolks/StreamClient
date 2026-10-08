//
//  PVRClientError.swift
//  PVR Client
//
//  Shared PVR client error types
//

import Foundation

enum PVRClientError: Error, LocalizedError {
    case notConfigured
    case authenticationFailed
    case sessionExpired
    case networkError(Error)
    case invalidResponse
    case apiError(String)
    /// The server is limiting sign-ins (HTTP 429); try again after the delay.
    case rateLimited(retryAfter: TimeInterval)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Server not configured"
        case .authenticationFailed:
            return "Authentication failed. Check your credentials."
        case .sessionExpired:
            return "Session expired. Please reconnect."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .apiError(let message):
            return message
        case .rateLimited(let retryAfter):
            return "The server is limiting sign-ins. Trying again in \(Int(retryAfter.rounded(.up))) s."
        }
    }
}
