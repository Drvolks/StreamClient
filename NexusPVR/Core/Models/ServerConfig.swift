//
//  ServerConfig.swift
//  nextpvr-apple-client
//
//  Server connection configuration - synced via iCloud
//

import Foundation

nonisolated struct ServerConfig: Codable, Equatable {
    var host: String
    var port: Int?
    var pin: String
    var username: String
    var password: String
    var apiKey: String
    var useHTTPS: Bool

    var effectivePort: Int {
        port ?? (useHTTPS ? 443 : 80)
    }

    /// True when the user typed an explicit http:// or https:// prefix in the host field.
    var hasExplicitScheme: Bool {
        let lower = host.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://")
    }

    /// True when the host field contains an explicit `:port` (with or without a scheme prefix).
    var hasExplicitPort: Bool {
        var remainder = host
        let lower = remainder.lowercased()
        if lower.hasPrefix("http://") {
            remainder = String(remainder.dropFirst("http://".count))
        } else if lower.hasPrefix("https://") {
            remainder = String(remainder.dropFirst("https://".count))
        }
        // Strip any path component.
        if let slash = remainder.firstIndex(of: "/") {
            remainder = String(remainder[..<slash])
        }
        guard let colon = remainder.firstIndex(of: ":") else { return false }
        let portPart = remainder[remainder.index(after: colon)...]
        return !portPart.isEmpty && portPart.allSatisfy { $0.isNumber }
    }

    /// Returns the explicit port embedded in the `host` field (e.g. "myserver:9191"), if any.
    var explicitHostPort: Int? {
        var remainder = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = remainder.lowercased()
        if lower.hasPrefix("http://") {
            remainder = String(remainder.dropFirst("http://".count))
        } else if lower.hasPrefix("https://") {
            remainder = String(remainder.dropFirst("https://".count))
        }
        if let slash = remainder.firstIndex(of: "/") {
            remainder = String(remainder[..<slash])
        }
        guard let colon = remainder.firstIndex(of: ":") else { return nil }
        let portPart = remainder[remainder.index(after: colon)...]
        return Int(portPart)
    }

    var baseURL: String {
        // Parse the host string into scheme / hostname / port / path so we never
        // double-prefix or double-port when the user types things like
        // "https://example.com" or "192.168.1.5:9191".
        var working = host.trimmingCharacters(in: .whitespacesAndNewlines)
        while working.hasSuffix("/") { working.removeLast() }

        let lower = working.lowercased()
        var explicitScheme: String? = nil
        if lower.hasPrefix("https://") {
            explicitScheme = "https"
            working = String(working.dropFirst("https://".count))
        } else if lower.hasPrefix("http://") {
            explicitScheme = "http"
            working = String(working.dropFirst("http://".count))
        }

        var path = ""
        if let slash = working.firstIndex(of: "/") {
            path = String(working[slash...])
            working = String(working[..<slash])
        }

        var embeddedPort: Int? = nil
        if let colon = working.firstIndex(of: ":") {
            let portStr = working[working.index(after: colon)...]
            if let p = Int(portStr) {
                embeddedPort = p
                working = String(working[..<colon])
            }
        }

        let scheme = explicitScheme ?? (useHTTPS ? "https" : "http")
        let defaultPort = scheme == "https" ? 443 : 80
        let finalPort = embeddedPort ?? port ?? defaultPort

        // Percent-encode hostname and path so stray spaces or other invalid
        // URL characters don't make URL(string:) return nil downstream.
        let encodedHost = working.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? working
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path

        if finalPort == defaultPort {
            return "\(scheme)://\(encodedHost)\(encodedPath)"
        }
        return "\(scheme)://\(encodedHost):\(finalPort)\(encodedPath)"
    }

    /// Display string for the server address (e.g. "192.168.1.100" or "192.168.1.100:8866")
    var displayAddress: String {
        if let port {
            return "\(host):\(port)"
        }
        return host
    }

    /// Editable, user-facing URL string. If `host` already contains a scheme,
    /// it's returned as-is; otherwise the legacy scheme/port fields are folded
    /// into a single string so the settings UI can present one text field.
    var editableURL: String {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return trimmed
        }
        let scheme = useHTTPS ? "https" : "http"
        let defaultPort = useHTTPS ? 443 : 80
        if let port, port != defaultPort {
            return "\(scheme)://\(trimmed):\(port)"
        }
        return "\(scheme)://\(trimmed)"
    }

    static var `default`: ServerConfig {
        ServerConfig(host: "", port: Brand.defaultPort, pin: Brand.defaultPIN, username: "", password: "", apiKey: "", useHTTPS: false)
    }

    var isDemoMode: Bool {
        host.lowercased() == "demo"
            || (username.lowercased() == "demo" && password == "demo")
            || apiKey.lowercased() == "demo"
    }

    var isConfigured: Bool {
        !host.isEmpty || isDemoMode
    }

    // Coding keys with defaults for backward compatibility
    enum CodingKeys: String, CodingKey {
        case host, port, pin, username, password, apiKey, useHTTPS
    }

    init(host: String, port: Int? = nil, pin: String, username: String = "", password: String = "", apiKey: String = "", useHTTPS: Bool) {
        self.host = host
        self.port = port
        self.pin = pin
        self.username = username
        self.password = password
        self.apiKey = apiKey
        self.useHTTPS = useHTTPS
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        host = try container.decode(String.self, forKey: .host)
        let decodedPort = try container.decodeIfPresent(Int.self, forKey: .port)
        port = (decodedPort == 0) ? nil : decodedPort
        pin = try container.decodeIfPresent(String.self, forKey: .pin) ?? ""
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        password = try container.decodeIfPresent(String.self, forKey: .password) ?? ""
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        useHTTPS = try container.decode(Bool.self, forKey: .useHTTPS)
    }
}

nonisolated extension ServerConfig {
    private static let storageKey = "ServerConfig"
    private static var ubiquitousStore: NSUbiquitousKeyValueStore { NSUbiquitousKeyValueStore.default }

    static let appGroupSuite: String = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String ?? ""

    // Legacy keys for migration
    private static let hostKey = "nextpvr_host"
    private static let portKey = "nextpvr_port"
    private static let pinKey = "nextpvr_pin"
    private static let useHTTPSKey = "nextpvr_use_https"

    static func load() -> ServerConfig {
        // Try iCloud first
        if let data = ubiquitousStore.data(forKey: storageKey),
           let config = try? JSONDecoder().decode(ServerConfig.self, from: data),
           config.isConfigured {
            // Also save locally as backup
            saveToUserDefaults(config)
            return config
        }

        // Fall back to UserDefaults for migration or offline use
        let defaults = UserDefaults.standard

        // Try new format first
        if let data = defaults.data(forKey: storageKey),
           let config = try? JSONDecoder().decode(ServerConfig.self, from: data),
           config.isConfigured {
            // Migrate to iCloud
            config.save()
            return config
        }

        // Try legacy format for migration
        let legacyHost = defaults.string(forKey: hostKey) ?? ""
        if !legacyHost.isEmpty {
            let config = ServerConfig(
                host: legacyHost,
                port: defaults.integer(forKey: portKey) == 0 ? nil : defaults.integer(forKey: portKey),
                pin: defaults.string(forKey: pinKey) ?? "",
                useHTTPS: defaults.bool(forKey: useHTTPSKey)
            )
            // Migrate to new format and iCloud
            config.save()
            // Clean up legacy keys
            defaults.removeObject(forKey: hostKey)
            defaults.removeObject(forKey: portKey)
            defaults.removeObject(forKey: pinKey)
            defaults.removeObject(forKey: useHTTPSKey)
            return config
        }

        return ServerConfig.default
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            // Save to iCloud for sync
            Self.ubiquitousStore.set(data, forKey: Self.storageKey)
            Self.ubiquitousStore.synchronize()

            // Also save locally as backup
            UserDefaults.standard.set(data, forKey: Self.storageKey)

            // Save to App Group for Top Shelf extension
            UserDefaults(suiteName: Self.appGroupSuite)?.set(data, forKey: Self.storageKey)
        }
    }

    static func clear() {
        ubiquitousStore.removeObject(forKey: storageKey)
        ubiquitousStore.synchronize()
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults(suiteName: appGroupSuite)?.removeObject(forKey: storageKey)
    }

    /// Load config from App Group UserDefaults (for use by extensions)
    static func loadFromAppGroup() -> ServerConfig {
        guard let data = UserDefaults(suiteName: appGroupSuite)?.data(forKey: storageKey),
              let config = try? JSONDecoder().decode(ServerConfig.self, from: data),
              config.isConfigured else {
            return ServerConfig(host: "", pin: "", useHTTPS: false)
        }
        return config
    }

    private static func saveToUserDefaults(_ config: ServerConfig) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    /// Call this to start observing iCloud sync changes
    static func startObservingSync(onChange: @escaping @Sendable (ServerConfig) -> Void) {
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: ubiquitousStore,
            queue: .main
        ) { _ in
            onChange(load())
        }
    }
}
