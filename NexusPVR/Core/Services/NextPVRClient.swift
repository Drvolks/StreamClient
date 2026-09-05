//
//  NextPVRClient.swift
//  nextpvr-apple-client
//
//  NextPVR API client with MD5 authentication
//

import Foundation
import Combine

@MainActor
final class NextPVRClient: ObservableObject, PVRClientProtocol {
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isConnecting = false
    @Published private(set) var lastError: NextPVRError?
    /// Set when a requested transcode couldn't be started and playback fell back
    /// to the original stream, so the player can say so once rather than leaving
    /// the user to wonder why their quality setting did nothing.
    @Published private(set) var streamQualityNotice: String?

    private(set) var config: ServerConfig
    private var sid: String?
    private let session: URLSession
    /// Session for user-initiated connect attempts. Unlike `session` it never
    /// waits for connectivity, so an unreachable or unresolvable host surfaces a
    /// real error in seconds instead of parking the Save spinner for minutes.
    private let connectSession: URLSession
    private let deviceName = Brand.deviceName
    private var authInProgress: Task<Void, Error>?
    private let networkEventLogger: any NetworkEventLogging
    private let networkPath: any NetworkPathReporting
    /// Channel of the live timeshift stream currently registered with the server,
    /// so it can be released on teardown or channel change.
    private var activeLiveChannelId: Int?
    /// Set while `startLiveStream` polls for readiness, before the stream is marked
    /// active — the readiness poll uses the same renewal call.
    private var isStartingLiveStream = false
    private var lastStreamInfoAt: Date = .distantPast
    /// Base `/live` URL of the active timeshift stream, used to build seek URLs.
    private var activeLiveStreamURL: URL?
    /// Channel of the server-side transcode currently running for this session,
    /// so it can be stopped on teardown or channel change. Mutually exclusive
    /// with `activeLiveChannelId`: a stream is either direct or transcoded.
    private var activeTranscodeChannelId: Int?

    /// Live TV stream quality, read from user preferences when a stream starts.
    /// Overridable so tests can drive the transcode path without writing to the
    /// shared preferences store.
    var streamQualityOverride: StreamQuality?

    /// Picks the quality to request for this stream.
    ///
    /// The cellular choice is honoured literally rather than only when it is
    /// lower: it is an explicit per-network setting, and second-guessing it
    /// would make the picker mean different things on different networks.
    ///
    /// Evaluated once, when the stream opens. Moving between Wi-Fi and cellular
    /// mid-programme doesn't re-negotiate — that would mean tearing down and
    /// restarting playback under the user.
    nonisolated static func effectiveStreamQuality(
        usual: StreamQuality,
        cellular: StreamQuality?,
        onMeteredNetwork: Bool
    ) -> StreamQuality {
        guard onMeteredNetwork, let cellular else { return usual }
        return cellular
    }

    /// How long to wait for the server-side buffer to fill before opening the
    /// stream anyway.
    private static let liveStreamReadyTimeout: TimeInterval = 5
    /// Buffer-state polling cadence, matching Kodi's `LeaseWorker`.
    private static let streamInfoInterval: TimeInterval = 10
    /// How long to wait for the server to spin up a transcode before giving up
    /// and falling back to the direct stream. Starting ffmpeg and filling the
    /// first HLS segments is slower than opening a tuner, so this is generous.
    private static let transcodeReadyTimeout: TimeInterval = 30
    /// Cadence of the `channel.transcode.status` poll, matching Kodi's.
    private static let transcodeStatusInterval: Duration = .seconds(1)

    init(config: ServerConfig? = nil,
         networkEventLogger: some NetworkEventLogging = Dependencies.networkEventLog,
         networkPath: any NetworkPathReporting = Dependencies.networkPathReporter) {
        self.config = config ?? ServerConfig.load()
        self.networkEventLogger = networkEventLogger
        self.networkPath = networkPath
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: configuration)

        let connectConfiguration = URLSessionConfiguration.default
        connectConfiguration.waitsForConnectivity = false
        connectConfiguration.timeoutIntervalForRequest = 15
        connectConfiguration.timeoutIntervalForResource = 30
        self.connectSession = URLSession(configuration: connectConfiguration)
    }

    var baseURL: String {
        config.baseURL
    }

    var isConfigured: Bool {
        config.isConfigured
    }

    func updateConfig(_ newConfig: ServerConfig) {
        config = newConfig
        sid = nil
        isAuthenticated = false
    }

    // MARK: - Network Logging

    private func sanitizePath(_ url: URL?) -> String {
        guard let url else { return "?" }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let sensitiveKeys: Set<String> = ["md5", "sid"]
        if let items = components?.queryItems {
            components?.queryItems = items.map { item in
                if sensitiveKeys.contains(item.name.lowercased()) {
                    return URLQueryItem(name: item.name, value: "***")
                }
                return item
            }
        }
        let path = components?.path ?? url.path
        if let query = components?.query, !query.isEmpty {
            return "\(path)?\(query)"
        }
        return path
    }

    private static let retryDelays: [Double] = [0.5, 1.0, 2.0, 4.0, 6.0]
    private static let maxAttempts = 5
    private static let retryableHTTPStatusCodes: Set<Int> = [408, 425, 429, 500, 502, 503, 504]
    private static let retryableURLErrorCodes: Set<URLError.Code> = [
        .timedOut,
        .cannotFindHost,
        .cannotConnectToHost,
        .networkConnectionLost,
        .dnsLookupFailed,
        .notConnectedToInternet,
        .internationalRoamingOff,
        .callIsActive,
        .dataNotAllowed,
        .cannotLoadFromNetwork,
        .secureConnectionFailed,
        .badServerResponse,
        .cannotParseResponse
    ]
    private static let retryablePOSIXErrorCodes: Set<POSIXErrorCode> = [
        .ECONNABORTED,
        .ECONNREFUSED,
        .ECONNRESET,
        .EPIPE,
        .ETIMEDOUT
    ]

    private func isRetryableNetworkError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return Self.retryableURLErrorCodes.contains(urlError.code)
        }
        return isRetryableNSError(error as NSError)
    }

    private func isRetryableNSError(_ error: NSError) -> Bool {
        networkEventLogger.log(NetworkEvent(
            timestamp: Date(),
            method: "RETRY",
            path: "/retryability/ns-error",
            statusCode: nil,
            isSuccess: false,
            durationMs: 0,
            responseSize: 0,
            errorDetail: "Inspecting NSError domain=\(error.domain) code=\(error.code) desc=\(error.localizedDescription)"
        ))

        if error.domain == NSURLErrorDomain {
            let code = URLError.Code(rawValue: error.code)
            if Self.retryableURLErrorCodes.contains(code) {
                return true
            }
        }

        if error.domain == NSPOSIXErrorDomain,
           let code = POSIXErrorCode(rawValue: Int32(error.code)),
           Self.retryablePOSIXErrorCodes.contains(code) {
            return true
        }

        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isRetryableNSError(underlying)
        }

        networkEventLogger.log(NetworkEvent(
            timestamp: Date(),
            method: "RETRY",
            path: "/retryability/ns-error",
            statusCode: nil,
            isSuccess: false,
            durationMs: 0,
            responseSize: 0,
            errorDetail: "NSError is not retryable; returning false for domain=\(error.domain) code=\(error.code)"
        ))
        return false
    }

    private func retryDelay(for attempt: Int) -> Double {
        let base = Self.retryDelays[min(attempt - 1, Self.retryDelays.count - 1)]
        // Small deterministic jitter to avoid hammering in lockstep.
        return base + Double(attempt) * 0.15
    }

    private func networkErrorDetail(_ error: Error, attempt: Int, willRetry: Bool) -> String {
        let nsError = error as NSError
        var parts: [String] = []

        if let urlError = error as? URLError {
            parts.append("URLError(\(urlError.code.rawValue): \(urlError.code))")
        } else if nsError.domain == NSURLErrorDomain {
            let code = URLError.Code(rawValue: nsError.code)
            parts.append("URLError(\(nsError.code): \(code))")
        } else {
            parts.append("\(nsError.domain)(\(nsError.code))")
        }

        if let nwPath = nsError.userInfo["NSURLErrorNWPathKey"] {
            parts.append("nwPath=\(nwPath)")
        } else if let legacyPath = nsError.userInfo["_NSURLErrorNWPathKey"] {
            parts.append("nwPath=\(legacyPath)")
        }

        if let failingURL = nsError.userInfo[NSURLErrorFailingURLErrorKey] {
            parts.append("url=\(failingURL)")
        } else if let failingURLString = nsError.userInfo["NSErrorFailingURLStringKey"] {
            parts.append("url=\(failingURLString)")
        }

        parts.append(error.localizedDescription)
        if willRetry {
            parts.append("(retrying \(attempt)/\(Self.maxAttempts))")
        }
        return parts.joined(separator: " ")
    }

    private func loggedData(from url: URL, connecting: Bool = false) async throws -> (Data, URLResponse) {
        let method = "GET"
        let path = sanitizePath(url)
        let session = connecting ? self.connectSession : self.session
        var lastError: Error?

        for attempt in 1...Self.maxAttempts {
            let start = CFAbsoluteTimeGetCurrent()
            networkEventLogger.log(NetworkEvent(
                timestamp: Date(), method: method, path: path,
                statusCode: nil, isSuccess: true,
                durationMs: 0, responseSize: 0,
                errorDetail: "Request started (attempt \(attempt)/\(Self.maxAttempts))"
            ))
            do {
                let (data, response) = try await session.data(from: url)
                let status = (response as? HTTPURLResponse)?.statusCode
                let ok = status.map { (200...399).contains($0) } ?? false
                let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                let shouldRetryHTTP = status.map { Self.retryableHTTPStatusCodes.contains($0) } ?? false

                if shouldRetryHTTP && attempt < Self.maxAttempts {
                    networkEventLogger.log(NetworkEvent(
                        timestamp: Date(), method: method, path: path,
                        statusCode: status, isSuccess: false,
                        durationMs: ms, responseSize: data.count,
                        errorDetail: "Transient HTTP \(status ?? -1), retrying \(attempt)/\(Self.maxAttempts)"
                    ))
                    let retryDelayNs = UInt64(retryDelay(for: attempt) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: retryDelayNs)
                    continue
                }

                networkEventLogger.log(NetworkEvent(
                    timestamp: Date(), method: method, path: path,
                    statusCode: status, isSuccess: ok,
                    durationMs: ms, responseSize: data.count,
                    errorDetail: ok ? nil : String(data: Data(data.prefix(1024)), encoding: .utf8)
                ))
                return (data, response)
            } catch {
                let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                lastError = error

                let isTransient = isRetryableNetworkError(error)
                let willRetry = isTransient && attempt < Self.maxAttempts
                networkEventLogger.log(NetworkEvent(
                    timestamp: Date(), method: method, path: path,
                    statusCode: nil, isSuccess: false,
                    durationMs: ms, responseSize: 0,
                    errorDetail: networkErrorDetail(error, attempt: attempt, willRetry: willRetry)
                ))

                if willRetry {
                    let retryDelayNs = UInt64(retryDelay(for: attempt) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: retryDelayNs)
                    continue
                }

                throw error
            }
        }

        throw lastError!
    }

    // MARK: - Authentication

    /// Stream URLs use SID directly and bypass API request 401 handling.
    /// Renewing the session at stream start avoids stale-SID playback failures.
    private func refreshSessionForStreaming() async throws {
        sid = nil
        isAuthenticated = false
        try await authenticate()
    }

    func authenticate() async throws {
        guard !config.isDemoMode else { isAuthenticated = true; return }

        guard config.isConfigured else {
            throw NextPVRError.notConfigured
        }

        // Coalesce concurrent auth calls — only one in-flight at a time
        if let existing = authInProgress {
            return try await existing.value
        }

        let task = Task {
            try await self.authenticateImpl()
        }
        authInProgress = task
        defer { authInProgress = nil }
        try await task.value
    }

    private func authenticateImpl() async throws {
        isConnecting = true
        lastError = nil

        defer { isConnecting = false }

        do {
            networkEventLogger.log(NetworkEvent(
                timestamp: Date(),
                method: "AUTH",
                path: "/session",
                statusCode: nil,
                isSuccess: true,
                durationMs: 0,
                responseSize: 0,
                errorDetail: "Starting NextPVR authentication against \(baseURL)"
            ))

            networkEventLogger.log(NetworkEvent(
                timestamp: Date(),
                method: "INFO",
                path: "/session",
                statusCode: nil,
                isSuccess: true,
                durationMs: 0,
                responseSize: 0,
                errorDetail: "Using server URL \(baseURL)"
            ))

            // Step 1: Initiate session
            guard let initiateURL = URL(string: "\(baseURL)/services/service?method=session.initiate&ver=1.0&device=\(deviceName)&format=json") else {
                throw NextPVRError.notConfigured
            }
            networkEventLogger.log(NetworkEvent(
                timestamp: Date(),
                method: "AUTH",
                path: "/session.initiate",
                statusCode: nil,
                isSuccess: true,
                durationMs: 0,
                responseSize: 0,
                errorDetail: "Preparing session initiation"
            ))
            let (initiateData, _) = try await loggedData(from: initiateURL, connecting: true)
            let initiateResponse = try JSONDecoder().decode(SessionInitiateResponse.self, from: initiateData)

            guard let tempSid = initiateResponse.sid, let salt = initiateResponse.salt else {
                networkEventLogger.log(NetworkEvent(
                    timestamp: Date(),
                    method: "AUTH",
                    path: "/session.initiate",
                    statusCode: nil,
                    isSuccess: false,
                    durationMs: 0,
                    responseSize: initiateData.count,
                    errorDetail: "Initiate response missing sid or salt"
                ))
                throw NextPVRError.invalidResponse
            }

            networkEventLogger.log(NetworkEvent(
                timestamp: Date(),
                method: "AUTH",
                path: "/session.initiate",
                statusCode: nil,
                isSuccess: true,
                durationMs: 0,
                responseSize: initiateData.count,
                errorDetail: "Received sid and salt"
            ))

            // Step 2: Compute hash: md5(":" + md5(PIN) + ":" + salt)
            let pinMd5 = MD5Hasher.hash(config.pin)
            let combined = ":\(pinMd5):\(salt)"
            let loginHash = MD5Hasher.hash(combined)

            // Step 3: Login
            guard let loginURL = URL(string: "\(baseURL)/services/service?method=session.login&sid=\(tempSid)&md5=\(loginHash)&format=json") else {
                throw NextPVRError.notConfigured
            }
            networkEventLogger.log(NetworkEvent(
                timestamp: Date(),
                method: "AUTH",
                path: "/session.login",
                statusCode: nil,
                isSuccess: true,
                durationMs: 0,
                responseSize: 0,
                errorDetail: "Submitting login request"
            ))
            let (loginData, _) = try await loggedData(from: loginURL, connecting: true)
            let loginResponse = try JSONDecoder().decode(SessionLoginResponse.self, from: loginData)

            if loginResponse.isSuccess {
                sid = tempSid
                isAuthenticated = true
                networkEventLogger.log(NetworkEvent(
                    timestamp: Date(),
                    method: "AUTH",
                    path: "/session.login",
                    statusCode: nil,
                    isSuccess: true,
                    durationMs: 0,
                    responseSize: loginData.count,
                    errorDetail: "Authentication succeeded"
                ))
            } else {
                networkEventLogger.log(NetworkEvent(
                    timestamp: Date(),
                    method: "AUTH",
                    path: "/session.login",
                    statusCode: nil,
                    isSuccess: false,
                    durationMs: 0,
                    responseSize: loginData.count,
                    errorDetail: "Authentication failed: session.login did not return ok"
                ))
                throw NextPVRError.authenticationFailed
            }
        } catch let error as NextPVRError {
            lastError = error
            networkEventLogger.log(NetworkEvent(
                timestamp: Date(),
                method: "AUTH",
                path: "/session",
                statusCode: nil,
                isSuccess: false,
                durationMs: 0,
                responseSize: 0,
                errorDetail: "Authentication error: \(error.localizedDescription)"
            ))
            throw error
        } catch {
            let npvrError = NextPVRError.networkError(error)
            lastError = npvrError
            networkEventLogger.log(NetworkEvent(
                timestamp: Date(),
                method: "AUTH",
                path: "/session",
                statusCode: nil,
                isSuccess: false,
                durationMs: 0,
                responseSize: 0,
                errorDetail: "Authentication threw unexpected error: \(error.localizedDescription)"
            ))
            throw npvrError
        }
    }

    func disconnect() {
        sid = nil
        isAuthenticated = false
    }

    // MARK: - API Requests

    private func request<T: Decodable>(_ method: String, params: [String: String] = [:]) async throws -> T {
        if !isAuthenticated {
            try await authenticate()
        }

        guard let sid else {
            throw NextPVRError.sessionExpired
        }

        var components = URLComponents(string: "\(baseURL)/services/service")!
        var queryItems = [
            URLQueryItem(name: "method", value: method),
            URLQueryItem(name: "sid", value: sid),
            URLQueryItem(name: "format", value: "json")
        ]

        for (key, value) in params {
            queryItems.append(URLQueryItem(name: key, value: value))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw NextPVRError.invalidResponse
        }

        do {
            let (data, response) = try await loggedData(from: url)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                // Session expired, re-authenticate
                isAuthenticated = false
                try await authenticate()
                return try await request(method, params: params)
            }

            return try JSONDecoder().decode(T.self, from: data)
        } catch let error as NextPVRError {
            throw error
        } catch is DecodingError {
            throw NextPVRError.invalidResponse
        } catch {
            throw NextPVRError.networkError(error)
        }
    }

    // MARK: - Channels

    func getChannels() async throws -> [Channel] {
        guard !config.isDemoMode else { return DemoDataProvider.channels }
        let response: ChannelListResponse = try await request("channel.list")
        return response.channels ?? []
    }

    // MARK: - EPG / Listings

    func getListings(channelId: Int) async throws -> [Program] {
        guard !config.isDemoMode else { return DemoDataProvider.listings(for: channelId) }
        let response: ProgramListingsResponse = try await request("channel.listings", params: ["channel_id": String(channelId)])
        return response.listings ?? []
    }

    /// Fetch listings for a single channel constrained to [start, end] (unix seconds).
    private func getListings(channelId: Int, start: Int, end: Int) async throws -> [Program] {
        guard !config.isDemoMode else { return DemoDataProvider.listings(for: channelId) }
        let response: ProgramListingsResponse = try await request("channel.listings", params: [
            "channel_id": String(channelId),
            "start": String(start),
            "end": String(end)
        ])
        return response.listings ?? []
    }

    func getAllListings(for channels: [Channel]) async throws -> [Int: [Program]] {
        try await fetchListingsConcurrently(for: channels, window: nil)
    }

    /// Fast first-paint: today + tomorrow only, fetched concurrently.
    func getFastListings(for channels: [Channel]) async throws -> [Int: [Program]] {
        let now = Int(Date().timeIntervalSince1970)
        // Cover roughly the visible guide window: 1h ago → 48h ahead.
        let start = now - 3600
        let end = now + 48 * 3600
        return try await fetchListingsConcurrently(for: channels, window: (start, end))
    }

    private func fetchListingsConcurrently(for channels: [Channel], window: (start: Int, end: Int)?) async throws -> [Int: [Program]] {
        guard !config.isDemoMode else { return DemoDataProvider.allListings(for: channels) }

        // Ensure we're authenticated once before kicking off concurrent requests.
        // After the SID is established, NextPVR safely handles concurrent calls on the same session.
        if !isAuthenticated {
            try await authenticate()
        }

        let concurrency = 10
        var result = [Int: [Program]]()
        result.reserveCapacity(channels.count)

        var index = 0
        try await withThrowingTaskGroup(of: (Int, [Program]).self) { group in
            // Prime the pipeline.
            while index < channels.count && index < concurrency {
                let channel = channels[index]
                group.addTask { [self] in
                    do {
                        let progs: [Program]
                        if let window {
                            progs = try await self.getListings(channelId: channel.id, start: window.start, end: window.end)
                        } else {
                            progs = try await self.getListings(channelId: channel.id)
                        }
                        return (channel.id, progs)
                    } catch {
                        return (channel.id, [])
                    }
                }
                index += 1
            }
            while let next = try await group.next() {
                result[next.0] = next.1
                if index < channels.count {
                    let channel = channels[index]
                    index += 1
                    group.addTask { [self] in
                        do {
                            let progs: [Program]
                            if let window {
                                progs = try await self.getListings(channelId: channel.id, start: window.start, end: window.end)
                            } else {
                                progs = try await self.getListings(channelId: channel.id)
                            }
                            return (channel.id, progs)
                        } catch {
                            return (channel.id, [])
                        }
                    }
                }
            }
        }

        return result
    }

    // MARK: - Recordings

    func getRecordings(filter: String = "ready") async throws -> [Recording] {
        guard !config.isDemoMode else { return [] }
        let response: RecordingListResponse = try await request("recording.list", params: ["filter": filter])
        return response.recordings ?? []
    }

    func getAllRecordings() async throws -> (completed: [Recording], recording: [Recording], scheduled: [Recording]) {
        guard !config.isDemoMode else { return DemoDataProvider.recordings() }
        // In TestFlight/Release cold starts, firing all three at once can race
        // with network path readiness on some devices. Keep this sequence stable.
        let readyResults = try await getRecordings(filter: "ready")
        let inProgressResults = try await getRecordings(filter: "recording")
        let pendingResults = try await getRecordings(filter: "pending")

        // Merge all results, deduplicating by ID
        // Prefer the version from "recording" filter, then "ready", then "pending"
        var recordingsById: [Int: Recording] = [:]
        for recording in pendingResults { recordingsById[recording.id] = recording }
        for recording in readyResults { recordingsById[recording.id] = recording }
        for recording in inProgressResults { recordingsById[recording.id] = recording }

        // Categorize by actual status rather than which filter returned them
        var completed: [Recording] = []
        var active: [Recording] = []
        var scheduled: [Recording] = []

        for recording in recordingsById.values {
            switch recording.recordingStatus {
            case .recording:
                active.append(recording)
            case .ready:
                completed.append(recording)
            case .pending, .conflict:
                scheduled.append(recording)
            default:
                completed.append(recording)
            }
        }

        return (completed, active, scheduled)
    }

    func scheduleRecording(eventId: Int) async throws {
        guard !config.isDemoMode else { DemoDataProvider.scheduleRecording(eventId: eventId); return }
        let response: APIResponse = try await request("recording.save", params: ["event_id": String(eventId)])
        if !response.isSuccess {
            throw NextPVRError.apiError("Failed to schedule recording")
        }
    }

    func scheduleSeriesRecording(eventId: Int) async throws {
        guard !config.isDemoMode else { DemoDataProvider.scheduleSeriesRecording(eventId: eventId); return }
        let response: APIResponse = try await request("recording.recurring.save", params: ["event_id": String(eventId)])
        if !response.isSuccess {
            throw NextPVRError.apiError("Failed to schedule series recording")
        }
    }

    func cancelRecording(recordingId: Int) async throws {
        guard !config.isDemoMode else { DemoDataProvider.cancelRecording(recordingId: recordingId); return }
        let response: APIResponse = try await request("recording.delete", params: ["recording_id": String(recordingId)])
        if !response.isSuccess {
            throw NextPVRError.apiError("Failed to cancel recording")
        }
    }

    func getRecurringRecordings() async throws -> [RecurringRecording] {
        guard !config.isDemoMode else { return DemoDataProvider.recurringRecordings() }
        let response: RecurringRecordingListResponse = try await request("recording.recurring.list")
        return response.recurrings ?? []
    }

    func cancelSeriesRecording(recurringId: Int) async throws {
        guard !config.isDemoMode else { DemoDataProvider.cancelSeriesRecording(recurringId: recurringId); return }
        let response: APIResponse = try await request("recording.recurring.delete", params: ["recurring_id": String(recurringId)])
        if !response.isSuccess {
            throw NextPVRError.apiError("Failed to cancel series recording")
        }
    }

    func setRecordingPosition(recordingId: Int, positionSeconds: Int) async throws {
        guard !config.isDemoMode else { return }
        // NextPVR ignores position=0, so use 1 to effectively reset to beginning
        let position = max(positionSeconds, 1)
        let _: APIResponse = try await request("recording.watched.set", params: [
            "recording_id": String(recordingId),
            "position": String(position)
        ])
    }

    // MARK: - Streaming URLs

    /// Opens a live stream using NextPVR's client-timeshift protocol:
    /// `channel.stream.start` registers a server-side timeshift buffer for this
    /// session, which is what makes `channel.stream.info` renewals valid (issue #120).
    ///
    /// The alternative "realtime" shape (`client=<device>-<uuid>`, no stream.start)
    /// has no renewal mechanism at all — the server reclaims the tuner 15s after the
    /// client stops reading, which is exactly what happens when mpv pauses behind its
    /// demuxer cache. Kodi makes the same split in `OpenLiveStream`; `client` being the
    /// SID rather than a device name is what its timeshift path sends.
    func liveStreamURL(channelId: Int) async throws -> URL {
        streamQualityNotice = nil
        guard !config.isDemoMode else { return DemoDataProvider.demoVideoURL }

        // Release any previous stream before rotating the SID, otherwise the old
        // handle lingers until the server times it out and may hold a tuner.
        await stopLiveStream()

        try await refreshSessionForStreaming()
        guard let sid else { throw NextPVRError.sessionExpired }

        // A transcoded stream is a different protocol, not a parameter on this
        // one: HLS off `channel.transcode.m3u8` rather than a raw transport
        // stream off `/live`. Falls through to the direct path when the server
        // can't transcode, so a misconfigured or overloaded server still plays.
        let prefs = UserPreferences.load()
        let quality = streamQualityOverride ?? Self.effectiveStreamQuality(
            usual: prefs.streamQuality,
            cellular: prefs.cellularStreamQuality,
            onMeteredNetwork: networkPath.prefersReducedData
        )
        // Say so when the metered-network rule changed the quality, so a picture
        // that looks worse than usual has a visible reason.
        if streamQualityOverride == nil, quality != prefs.streamQuality {
            streamQualityNotice = "On a metered network — playing at \(quality.label)."
        }

        if let profile = quality.profileName {
            if let url = await startTranscodedStream(channelId: channelId, profile: profile, sid: sid) {
                return url
            }
            // Every reason for landing here is logged in detail by
            // `startTranscodedStream`; this is the one-line version the player
            // shows, so a dropped quality setting is never silent.
            streamQualityNotice = "The server couldn't transcode to \(profile) — "
                + "playing at original quality."
        }

        // Degrade to the realtime shape if the server won't start a timeshift
        // stream (older NextPVR, no free tuner). Playback still works; it just
        // can't survive a long pause, which is the pre-existing behaviour.
        let timeshifted = await startLiveStream(channelId: channelId)
        activeLiveChannelId = timeshifted ? channelId : nil

        var components = URLComponents(string: "\(baseURL)/live")
        components?.queryItems = [
            URLQueryItem(name: "channeloid", value: String(channelId)),
            URLQueryItem(name: "client", value: timeshifted ? sid : "\(deviceName)-\(sid)"),
            URLQueryItem(name: "sid", value: sid)
        ]
        guard let url = components?.url else {
            throw NextPVRError.invalidResponse
        }
        activeLiveStreamURL = timeshifted ? url : nil
        return url
    }

    /// URL that replays the timeshift buffer from `byteOffset`, for seeking within
    /// a live stream. NextPVR can't seek an open `/live` response, so the player has
    /// to reopen at an offset — the same thing `ClientTimeShift::Seek` does. The
    /// trailing `-` makes it an open-ended range.
    ///
    /// Returns nil when the stream isn't timeshifted, i.e. there's nothing to seek in.
    func liveStreamSeekURL(byteOffset: Int64) -> URL? {
        guard let base = activeLiveStreamURL,
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return nil
        }
        var items = (components.queryItems ?? []).filter { $0.name != "seek" }
        items.append(URLQueryItem(name: "seek", value: "\(max(0, byteOffset))-"))
        components.queryItems = items
        return components.url
    }

    /// Registers the server-side timeshift buffer and waits briefly for it to hold
    /// enough data to be playable. Kodi waits for 50KB before opening the stream;
    /// we cap the wait so a slow tuner can't stall the UI — mpv copes with an early
    /// open, it just buffers a little longer.
    ///
    /// Returns whether the timeshift stream was registered. A failure is not fatal:
    /// the caller falls back to a plain realtime stream.
    private func startLiveStream(channelId: Int) async -> Bool {
        do {
            try await streamAction("channel.stream.start", params: ["channel_id": String(channelId)])
        } catch {
            print("[NextPVR] channel.stream.start failed, falling back to realtime "
                + "stream (no pause keepalive): \(error.localizedDescription)")
            return false
        }

        isStartingLiveStream = true
        defer { isStartingLiveStream = false }
        lastStreamInfoAt = .distantPast

        let deadline = Date().addingTimeInterval(Self.liveStreamReadyTimeout)
        while Date() < deadline {
            if let info = try? await fetchStreamInfo(), info.streamLength > 50_000 {
                break
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return true
    }

    /// True while a timeshift handle or a transcode is open on the server. Guards
    /// the foreground re-authentication, which would otherwise rotate the SID that
    /// owns it — the transcode playlist URL carries the SID too, so re-auth would
    /// break a transcoded stream just as surely as a direct one.
    var hasActiveLiveStream: Bool { activeLiveChannelId != nil || activeTranscodeChannelId != nil }

    /// Releases the server-side timeshift buffer so the tuner is freed immediately
    /// rather than after the 15s renewal timeout. Best-effort: teardown must not
    /// throw or block.
    func stopLiveStream() async {
        guard !config.isDemoMode else { return }
        if activeTranscodeChannelId != nil {
            await stopTranscodedStream()
        }
        guard activeLiveChannelId != nil else { return }
        activeLiveChannelId = nil
        activeLiveStreamURL = nil
        _ = try? await streamAction("channel.stream.stop")
    }

    /// Issues one of the `channel.stream.*` methods. These live under `/service`
    /// (not `/services/service` like every other method here) and answer raw XML.
    @discardableResult
    private func streamAction(_ method: String, params: [String: String] = [:]) async throws -> Data {
        guard let sid else { throw NextPVRError.sessionExpired }

        var components = URLComponents(string: "\(baseURL)/service")!
        var items = [
            URLQueryItem(name: "method", value: method),
            URLQueryItem(name: "sid", value: sid)
        ]
        for (key, value) in params {
            items.append(URLQueryItem(name: key, value: value))
        }
        components.queryItems = items
        guard let url = components.url else {
            throw NextPVRError.invalidResponse
        }

        let (data, response) = try await loggedData(from: url)
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200...299).contains(status) {
            throw NextPVRError.apiError("\(method) failed with HTTP \(status)")
        }
        return data
    }

    // MARK: - Transcoded streaming

    /// Asks the server to transcode a channel and returns the HLS playlist URL
    /// once it is playable, or nil if it never becomes playable.
    ///
    /// NextPVR only transcodes when a client asks: `channel.transcode.initiate`
    /// starts ffmpeg with a named server-side profile (`720p`, `480p`, …),
    /// `channel.transcode.status` counts to 100 while it fills the first
    /// segments, and the stream is then served as HLS from
    /// `channel.transcode.m3u8`. This is Kodi's `Transcoded` streaming method.
    ///
    /// Returning nil is not an error — the caller falls back to the direct
    /// stream, which is worse for bandwidth but always works.
    private func startTranscodedStream(channelId: Int, profile: String, sid: String) async -> URL? {
        do {
            let response = try await streamAction("channel.transcode.initiate", params: [
                "force": "true",
                "channel_id": String(channelId),
                "profile": profile
            ])
            // NextPVR rejects an undefined profile with `<rsp stat="fail">` at
            // HTTP 200, so the status code alone doesn't say the transcode
            // started, and `loggedData` records no body for a 200. Log the
            // answer either way — a silent fallback is indistinguishable from
            // the feature not working at all.
            if let failure = Self.transcodeFailure(response) {
                logTranscode("initiate refused profile '\(profile)': \(failure). "
                    + "Falling back to the direct stream.", isSuccess: false)
                return nil
            }
            logTranscode("initiate accepted profile '\(profile)' for channel \(channelId)",
                         isSuccess: true)
        } catch {
            logTranscode("initiate failed: \(error.localizedDescription). "
                + "Falling back to the direct stream.", isSuccess: false)
            return nil
        }

        // Claim the session now: the transcode has to be stopped even if it
        // never becomes playable, or it holds the tuner until the server times out.
        activeTranscodeChannelId = channelId

        var lastPercentage = -1
        let deadline = Date().addingTimeInterval(Self.transcodeReadyTimeout)
        while Date() < deadline {
            do {
                let data = try await streamAction("channel.transcode.status")
                // A transcode whose ffmpeg died reports `stat="fail"` here too,
                // with no <percentage> — stop rather than waiting out the timeout.
                if let failure = Self.transcodeFailure(data) {
                    logTranscode("transcode failed after starting: \(failure). "
                        + "Falling back to the direct stream.", isSuccess: false)
                    break
                }
                guard let progress = Self.parseTranscodeStatus(data) else {
                    logTranscode("status was unparseable: "
                        + "\((String(data: Data(data.prefix(256)), encoding: .utf8) ?? "<unreadable>").trimmingCharacters(in: .whitespacesAndNewlines))",
                        isSuccess: false)
                    try? await Task.sleep(for: Self.transcodeStatusInterval)
                    continue
                }
                if progress.percentage != lastPercentage {
                    lastPercentage = progress.percentage
                    logTranscode("status \(progress.percentage)%\(progress.isFinal ? " (final)" : "")",
                                 isSuccess: true)
                }
                if progress.isReady {
                    var components = URLComponents(string: "\(baseURL)/service")
                    components?.queryItems = [
                        URLQueryItem(name: "method", value: "channel.transcode.m3u8"),
                        URLQueryItem(name: "sid", value: sid)
                    ]
                    if let url = components?.url {
                        logTranscode("ready — playing \(profile) HLS stream", isSuccess: true)
                        return url
                    }
                    break
                }
                if progress.hasFailed {
                    logTranscode("stalled at \(progress.percentage)% — the server stopped making "
                        + "progress. It may be unable to transcode \(profile) in real time, or the "
                        + "transcoder is not configured. Falling back to the direct stream.",
                        isSuccess: false)
                    break
                }
            } catch {
                logTranscode("status request failed: \(error.localizedDescription)", isSuccess: false)
            }
            try? await Task.sleep(for: Self.transcodeStatusInterval)
        }

        if lastPercentage < 100 {
            logTranscode("gave up after \(Int(Self.transcodeReadyTimeout))s at \(lastPercentage)%. "
                + "Falling back to the direct stream.", isSuccess: false)
        }
        await stopTranscodedStream()
        return nil
    }

    /// Records a step of the transcode negotiation in the in-app event log
    /// (Settings > Event Log) as well as the console. These steps decide whether
    /// the user's chosen quality is honoured or silently dropped, so they have to
    /// be visible without a debugger attached.
    private func logTranscode(_ message: String, isSuccess: Bool) {
        print("[NextPVR] transcode: \(message)")
        networkEventLogger.log(NetworkEvent(
            timestamp: Date(),
            method: "TRANSCODE",
            path: "/service?method=channel.transcode.*",
            statusCode: nil,
            isSuccess: isSuccess,
            durationMs: 0,
            responseSize: 0,
            errorDetail: message
        ))
    }

    /// Releases the server-side transcode so ffmpeg exits and the tuner is freed
    /// immediately. Best-effort: teardown must not throw or block.
    private func stopTranscodedStream() async {
        guard activeTranscodeChannelId != nil else { return }
        activeTranscodeChannelId = nil
        _ = try? await streamAction("channel.transcode.stop")
    }

    /// Parses the document returned by `channel.transcode.status`. Like the other
    /// `/service` stream methods it answers raw XML, so it can't go through
    /// `request(_:params:)`.
    /// Reads a refusal out of any `channel.transcode.*` response, returning the
    /// server's own wording, or nil when the response is not a refusal.
    ///
    /// NextPVR reports these at HTTP 200: it accepts the request, spawns ffmpeg,
    /// and only then discovers the encode cannot run — a missing streaming
    /// profile, or a hardware encoder it can't open. Reading the body is the
    /// only way to tell a started transcode from a dead one.
    nonisolated static func transcodeFailure(_ data: Data) -> String? {
        let parser = TranscodeStatusXMLParser()
        guard parser.parse(data), parser.stat == "fail" else { return nil }
        let message = parser.errorMessage ?? "no message"
        guard let code = parser.errorCode else { return message }
        return "\(message) (err \(code))"
    }

    nonisolated static func parseTranscodeStatus(_ data: Data) -> TranscodeProgress? {
        let parser = TranscodeStatusXMLParser()
        guard parser.parse(data), let percentage = parser.percentage else {
            return nil
        }
        return TranscodeProgress(percentage: percentage, isFinal: parser.isFinal ?? false)
    }

    func recordingStreamURL(recordingId: Int) async throws -> URL {
        guard !config.isDemoMode else { return DemoDataProvider.demoVideoURL }
        try await refreshSessionForStreaming()
        guard let sid else { throw NextPVRError.sessionExpired }
        guard let url = URL(string: "\(baseURL)/live?recording=\(recordingId)&sid=\(sid)") else {
            throw NextPVRError.invalidResponse
        }
        return url
    }

    /// Renews the live stream handle. NextPVR expires a live stream (releasing the
    /// tuner and deleting the timeshift buffer) if the client goes 15 seconds without
    /// a renewal, which is what happens once mpv stops reading the socket on pause.
    ///
    /// `channel.transcode.lease` is the renewal — `channel.stream.info` only reports
    /// state, so polling it alone lets the stream expire mid-playback. Kodi's
    /// `LeaseWorker` sends the lease every 7s and stream.info every 10s; this mirrors
    /// that, with the info call throttled since it's only for buffer state.
    ///
    /// Deliberately never rotates the SID: the renewal has to target the session that
    /// opened `/live`, so calling `refreshSessionForStreaming()` here would orphan the
    /// handle we're trying to keep alive.
    @discardableResult
    func renewLiveStream() async throws -> LiveStreamInfo? {
        guard !config.isDemoMode else { return nil }
        // A transcoded stream renews itself: the player's playlist and segment
        // requests are what keep it alive, and there is no timeshift buffer to
        // report on. Kodi's `TranscodedBuffer` skips both calls for the same
        // reason — sending them here would just 404 every tick.
        guard activeTranscodeChannelId == nil else { return nil }
        // Nothing to renew when the stream fell back to realtime — the server would
        // just 404, once every keepalive tick.
        guard activeLiveChannelId != nil || isStartingLiveStream else { return nil }

        // Tolerate a failed lease rather than dropping out of the loop: a server that
        // doesn't implement it shouldn't stop us fetching buffer state.
        do {
            try await streamAction("channel.transcode.lease")
        } catch {
            print("[NextPVR] channel.transcode.lease failed: \(error.localizedDescription)")
        }

        guard Date().timeIntervalSince(lastStreamInfoAt) >= Self.streamInfoInterval else {
            return nil
        }
        lastStreamInfoAt = Date()
        return try await fetchStreamInfo()
    }

    /// Fetches the timeshift buffer state. Reports only — does not renew the handle.
    @discardableResult
    private func fetchStreamInfo() async throws -> LiveStreamInfo? {
        guard let sid else { throw NextPVRError.sessionExpired }

        // NextPVR only routes this method under `/service` — `/services/service`
        // (used by every other method here) answers 404.
        var components = URLComponents(string: "\(baseURL)/service")!
        components.queryItems = [
            URLQueryItem(name: "method", value: "channel.stream.info"),
            URLQueryItem(name: "sid", value: sid)
        ]
        guard let url = components.url else {
            throw NextPVRError.invalidResponse
        }

        let (data, response) = try await loggedData(from: url)
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200...299).contains(status) {
            // A 404 here means the server already dropped the stream — surface it
            // rather than returning a silent nil.
            throw NextPVRError.apiError("channel.stream.info failed with HTTP \(status)")
        }
        // An unparseable body isn't fatal; it just means no buffer state this tick.
        return Self.parseStreamInfo(data)
    }

    /// Parses the `<map>` document returned by `channel.stream.info`. This method
    /// answers with raw XML rather than the usual JSON method response, so it can't
    /// go through `request(_:params:)`.
    nonisolated static func parseStreamInfo(_ data: Data) -> LiveStreamInfo? {
        let parser = StreamInfoXMLParser()
        guard parser.parse(data),
              let duration = parser.streamDuration,
              let length = parser.streamLength else {
            return nil
        }
        return LiveStreamInfo(
            streamDurationMs: duration,
            streamLength: length,
            isComplete: parser.isComplete ?? false
        )
    }

    func clearStreamQualityNotice() {
        streamQualityNotice = nil
    }

    func streamAuthHeaders() -> [String: String] {
        [:]  // NextPVR uses SID in URL
    }

    func channelIconURL(channelId: Int) throws -> URL? {
        guard !config.isDemoMode else { return DemoDataProvider.channelIconURL(channelId: channelId) }
        guard let sid else { throw NextPVRError.sessionExpired }
        return URL(string: "\(baseURL)/service?method=channel.icon&channel_id=\(channelId)&sid=\(sid)")
    }

    func recordingArtworkURL(recordingId: Int, fanart: Bool) -> URL? {
        guard !config.isDemoMode else { return DemoDataProvider.recordingArtworkURL(recordingId: recordingId, fanart: fanart) }
        var components = URLComponents(string: "\(baseURL)/services/service")
        var items: [URLQueryItem] = [
            URLQueryItem(name: "method", value: "recording.artwork"),
            URLQueryItem(name: "recording_id", value: String(recordingId)),
            URLQueryItem(name: "with_placeholder", value: "true")
        ]
        if fanart {
            items.append(URLQueryItem(name: "fanart", value: "true"))
        }
        components?.queryItems = items
        return components?.url
    }
}
