import Foundation

/// Estimates the growing duration of an in-progress recording via HTTP HEAD
/// requests, without disrupting playback.
///
/// EOF handling (reload at current position) is done by `MPVPlayerCore`'s
/// position-polling timer via `checkRecordingEOF()`. This class provides
/// updated duration estimates so the player can reload proactively before
/// EOF when possible.
nonisolated final class MPVRecordingMonitor {
    private(set) var currentURL: String?

    private var baselineDuration: Double = 0
    private var baselineContentLength: Int64 = 0
    private var baselineCaptured = false
    private var _estimatedDuration: Double = 0
    private var lastRefreshTime: Date = .distantPast
    private var refreshInFlight = false

    var headers: [String: String] = [:]
    var recordingStartTime: Date?

    /// How often to poll the server (seconds). HEAD requests are just headers
    /// (few hundred bytes), so polling frequently is fine.
    var refreshInterval: TimeInterval = 2

    /// Called periodically with the estimated total duration (seconds).
    var onDurationEstimate: ((Double) -> Void)?

    /// Called when the recording finishes (detected by MPVPlayerCore when
    /// two consecutive EOFs yield the same duration).
    var onRecordingFinished: (() -> Void)?

    /// The latest estimated duration. Returns 0 if no estimate is available.
    var estimatedDuration: Double { _estimatedDuration }

    private var isHLS: Bool {
        guard let currentURL else { return false }
        let lower = currentURL.lowercased()
        return lower.hasSuffix(".m3u8") || lower.contains("/hls/")
    }

    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    /// No-op kept for call-site compatibility.
    func configure(mpv: OpaquePointer) {}

    /// Start duration estimation. Call after `mpv_initialize()` and `loadfile`.
    func start(mpv: OpaquePointer, url: String, startTime: Date? = nil, headers: [String: String] = [:]) {
        let effectiveStart = startTime ?? self.recordingStartTime
        let effectiveHeaders = headers.isEmpty ? self.headers : headers
        stop()
        self.currentURL = url
        self.recordingStartTime = effectiveStart
        self.headers = effectiveHeaders
        baselineCaptured = false
        if let start = recordingStartTime {
            _estimatedDuration = max(0, Date().timeIntervalSince(start))
        } else {
            _estimatedDuration = 0
        }
        lastRefreshTime = .distantPast
        print("RecordingMonitor: started for \(url) (initial duration=\(_estimatedDuration)s)")
    }

    /// Stop estimation.
    func stop() {
        currentURL = nil
        baselineCaptured = false
        _estimatedDuration = 0
        headers = [:]
        recordingStartTime = nil
    }

    /// Call periodically (e.g. from the position-polling timer) with the
    /// current mpv duration so the monitor can capture its baseline.
    func updateBaseline(duration: Double) {
        guard !baselineCaptured else { return }

        if isHLS {
            var initial = duration
            if let start = recordingStartTime {
                initial = max(initial, Date().timeIntervalSince(start))
            }
            if initial > 0 {
                baselineDuration = initial
                _estimatedDuration = initial
                baselineCaptured = true
                print("RecordingMonitor: HLS baseline set to \(String(format: "%.1f", initial))s")
                fetchHLSPlaylistDuration { [weak self] hlsDuration in
                    guard let self else { return }
                    self._estimatedDuration = max(self._estimatedDuration, hlsDuration)
                    self.onDurationEstimate?(self._estimatedDuration)
                }
            }
            return
        }

        guard duration > 0 else { return }
        baselineDuration = duration
        _estimatedDuration = duration
        baselineCaptured = true

        fetchContentLength { [weak self] size in
            guard let self else { return }
            self.baselineContentLength = size
            print("RecordingMonitor: baseline captured — "
                + "duration=\(String(format: "%.1f", duration))s, "
                + "size=\(size) bytes")
        }
    }

    /// Reset the baseline so it gets recaptured on the next `updateBaseline`
    /// call (e.g. after a stream reload).
    func resetBaseline() {
        baselineCaptured = false
    }

    /// Called every position-polling tick (~0.5s). Fires a refresh request if
    /// enough time has elapsed.
    func refreshIfNeeded() {
        guard !refreshInFlight else { return }

        if isHLS {
            guard currentURL != nil else { return }
            // Update immediately based on elapsed time if recordingStartTime is present
            if let start = recordingStartTime {
                let elapsed = max(0, Date().timeIntervalSince(start))
                if elapsed > _estimatedDuration {
                    _estimatedDuration = elapsed
                    onDurationEstimate?(elapsed)
                }
            }

            guard Date().timeIntervalSince(lastRefreshTime) >= refreshInterval else { return }
            lastRefreshTime = Date()
            refreshInFlight = true

            fetchHLSPlaylistDuration { [weak self] hlsDuration in
                guard let self else { return }
                self.refreshInFlight = false
                if hlsDuration > 0 {
                    self._estimatedDuration = max(self._estimatedDuration, hlsDuration)
                    self.onDurationEstimate?(self._estimatedDuration)
                }
            }
            return
        }

        guard baselineContentLength > 0, baselineDuration > 0 else { return }
        guard Date().timeIntervalSince(lastRefreshTime) >= refreshInterval else { return }

        lastRefreshTime = Date()
        refreshInFlight = true

        fetchContentLength { [weak self] newSize in
            guard let self, newSize > 0 else {
                self?.refreshInFlight = false
                return
            }
            let estimated = self.baselineDuration * Double(newSize) / Double(self.baselineContentLength)
            self._estimatedDuration = estimated
            self.refreshInFlight = false
            self.onDurationEstimate?(estimated)
        }
    }

    // MARK: - Private

    private func fetchHLSPlaylistDuration(completion: @escaping (Double) -> Void) {
        guard let urlString = currentURL, let url = URL(string: urlString) else {
            refreshInFlight = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }

        urlSession.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                self.refreshInFlight = false
                return
            }

            if let durHeader = http.value(forHTTPHeaderField: "X-Recording-Total-Duration"),
               let headerDuration = Double(durHeader), headerDuration > 0 {
                completion(headerDuration)
                return
            }

            guard let data = data,
                  let text = String(data: data, encoding: .utf8) else {
                self.refreshInFlight = false
                return
            }

            var total: Double = 0
            for line in text.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#EXTINF:") {
                    let segPart = trimmed.dropFirst(8)
                    let numStr = segPart.split(separator: ",")[0].trimmingCharacters(in: .whitespaces)
                    if let d = Double(numStr) {
                        total += d
                    }
                }
            }
            completion(total)
        }.resume()
    }

    private func fetchContentLength(completion: @escaping (Int64) -> Void) {
        guard let urlString = currentURL, let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }

        urlSession.dataTask(with: request) { _, response, _ in
            guard let http = response as? HTTPURLResponse,
                  let clStr = http.value(forHTTPHeaderField: "Content-Length"),
                  let cl = Int64(clStr), cl > 0 else { return }
            completion(cl)
        }.resume()
    }
}
