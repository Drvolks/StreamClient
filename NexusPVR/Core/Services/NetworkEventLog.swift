//
//  NetworkEventLog.swift
//  DispatcherPVR
//
//  Observable event log for HTTP requests to the Dispatcharr backend
//

import Foundation
import Combine

struct NetworkEvent: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let method: String
    let path: String
    let statusCode: Int?
    let isSuccess: Bool
    let durationMs: Int
    let responseSize: Int
    let errorDetail: String?
    /// Host the request or stream went to, with a non-default port when one
    /// was used (e.g. "pvr.example.com" or "192.168.1.50:8866"). Tells the
    /// server address and the custom host apart in the log (#165).
    var host: String? = nil

    /// "host" or "host:port" for `url`; nil when it has no host.
    nonisolated static func hostLabel(for url: URL?) -> String? {
        guard let url, let host = url.host, !host.isEmpty else { return nil }
        if let port = url.port { return "\(host):\(port)" }
        return host
    }
}

/// Protocol for logging network events — allows test doubles and alternative implementations.
protocol NetworkEventLogging: AnyObject, Sendable {
    nonisolated func log(_ event: NetworkEvent)
}

/// Concrete observable implementation for network event logging.
@MainActor
final class NetworkEventLog: ObservableObject, NetworkEventLogging {
    @Published private(set) var events: [NetworkEvent] = []
    private let maxEvents = 200

    nonisolated init() {}

    nonisolated func log(_ event: NetworkEvent) {
        Task { @MainActor in
            self.events.append(event)
            if self.events.count > self.maxEvents {
                self.events.removeFirst(self.events.count - self.maxEvents)
            }
            #if DEBUG
            print(Self.consoleLine(for: event))
            #endif
        }
    }

    func clear() {
        events.removeAll()
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var formattedLog: String {
        events.map { event in
            Self.consoleLine(for: event)
        }.joined(separator: "\n")
    }

    static func consoleLine(for event: NetworkEvent) -> String {
        let time = timeFormatter.string(from: event.timestamp)
        let status = event.statusCode.map { " → \($0)" } ?? (event.isSuccess ? "" : " → ERR")
        let duration = event.durationMs > 0 ? " (\(event.durationMs)ms)" : ""
        let host = event.host.map { " [\($0)]" } ?? ""
        var line = "\(time) \(event.method)\(host) \(event.path)\(status)\(duration)"
        if let detail = event.errorDetail {
            line += "\n  \(detail)"
        }
        return line
    }
}
