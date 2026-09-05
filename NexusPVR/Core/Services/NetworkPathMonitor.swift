//
//  NetworkPathMonitor.swift
//  PVR Client
//
//  Reports whether the current network is one the user would rather not stream
//  full-bitrate video over.
//

import Foundation
import Network

/// Protocol so callers can be tested without a real network path.
nonisolated protocol NetworkPathReporting: AnyObject, Sendable {
    /// True when the active path is metered or the user has asked for less data:
    /// cellular, a personal hotspot, or Low Data Mode.
    var prefersReducedData: Bool { get }
}

/// Watches the default network path.
///
/// Deliberately keyed on `isExpensive` / `isConstrained` rather than on the
/// interface type: `isExpensive` covers a personal hotspot as well as cellular,
/// and `isConstrained` is the user having switched on Low Data Mode, which is a
/// direct request to use less data and worth honouring for the same reason.
///
/// Reads happen while a stream is being opened, so the value is kept in a plain
/// lock-guarded field rather than behind an actor — the caller must not have to
/// await it.
nonisolated final class NetworkPathMonitor: NetworkPathReporting, @unchecked Sendable {
    static let shared = NetworkPathMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkPathMonitor")
    private let lock = NSLock()
    private var _prefersReducedData = false
    private var started = false

    var prefersReducedData: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _prefersReducedData
    }

    /// Begins watching. Safe to call more than once.
    func start() {
        lock.lock()
        guard !started else { return lock.unlock() }
        started = true
        lock.unlock()

        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let reduced = path.isExpensive || path.isConstrained
            self.lock.lock()
            self._prefersReducedData = reduced
            self.lock.unlock()
        }
        monitor.start(queue: queue)
    }
}
