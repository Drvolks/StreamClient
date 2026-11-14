//
//  LogShareServer.swift
//  PVR Client
//
//  Serves a log to other devices on the network while the Apple TV's
//  share screen is open.
//

#if os(tvOS)
import Foundation
import Network
import Combine

/// Apple TV has no share sheet, so a log is shared as a plain-text page on
/// the local network: `TVLogShareView` shows its address as a QR code, and
/// the page lives only while that screen is open. The path carries a random
/// token; anything else gets a 404.
@MainActor
final class LogShareServer: ObservableObject {
    @Published private(set) var status: LogShareStatus = .starting
    private var listener: NWListener?

    func start(text: String, fileName: String) {
        stop()
        status = .starting
        let token = LogShareHTTP.makeToken()
        let body = Data(text.utf8)
        let listener: NWListener
        do {
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = false
            listener = try NWListener(using: parameters)
        } catch {
            status = .failed(error.localizedDescription)
            return
        }
        listener.newConnectionHandler = { @Sendable connection in
            Self.serve(connection, token: token, fileName: fileName, body: body)
        }
        listener.stateUpdateHandler = { @Sendable [weak self] state in
            let port = listener.port?.rawValue
            Task { @MainActor in
                self?.handle(state, port: port, path: LogShareHTTP.path(token: token, fileName: fileName))
            }
        }
        self.listener = listener
        listener.start(queue: .global(qos: .userInitiated))
    }

    func stop() {
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
    }

    private func handle(_ state: NWListener.State, port: UInt16?, path: String) {
        switch state {
        case .ready:
            guard let port, let address = LocalNetworkAddress.ipv4(),
                  let url = URL(string: "http://\(address):\(port)\(path)") else {
                status = .failed("This Apple TV has no local network address.")
                return
            }
            status = .ready(url)
        case .failed(let error):
            status = .failed(error.localizedDescription)
        default:
            break
        }
    }

    nonisolated private static func serve(_ connection: NWConnection, token: String, fileName: String, body: Data) {
        connection.start(queue: .global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { @Sendable data, _, _, error in
            guard let data, error == nil else {
                connection.cancel()
                return
            }
            let response = LogShareHTTP.response(for: data, token: token, fileName: fileName, body: body)
            connection.send(content: response, completion: .contentProcessed { @Sendable _ in
                connection.cancel()
            })
        }
    }
}
#endif
