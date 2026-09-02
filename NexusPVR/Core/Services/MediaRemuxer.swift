//
//  MediaRemuxer.swift
//  NexusPVR
//
//  Stream-copy remux of a network stream into a local file, using the
//  libavformat that already ships with MPVKit.
//

import Foundation
import Libavformat
import Libavcodec
import Libavutil

/// Pulls an HTTP stream and writes it to disk as a seekable file, copying the
/// packets through untouched (no decode, no encode).
///
/// This is what makes an offline copy of a Dispatcharr catch-up programme
/// possible at all: the catch-up proxy serves raw, unindexed MPEG-TS with no
/// file extension (see `MPVPlayerCore.loadURL`), which is neither seekable nor
/// something QuickTime will open. Remuxing into MP4 gives a real index, and
/// because nothing is re-encoded the job runs as fast as the server delivers
/// bytes rather than at playback speed.
///
/// Threading: `av_read_frame` blocks, so the whole job runs on its own queue
/// and the async entry point bridges it back. Cancellation goes through
/// libavformat's interrupt callback, which is the only way to break out of a
/// blocking network read.
/// `nonisolated` on purpose: the project defaults to main-actor isolation
/// (`SWIFT_DEFAULT_ACTOR_ISOLATION`), and this class exists precisely to do its
/// blocking work off the main thread.
nonisolated final class MediaRemuxer: @unchecked Sendable {

    nonisolated struct Result: Sendable {
        /// Where the file actually landed — the extension can differ from the
        /// requested one when the MP4 muxer refuses a codec (see `run`).
        let url: URL
        /// Seconds of programme written.
        let seconds: Double
        let bytes: Int64
    }

    nonisolated enum RemuxError: LocalizedError, Equatable {
        case openInput(String)
        case noPlayableStreams
        case openOutput(String)
        case writeFailed(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .openInput(let detail): return "Couldn't open the stream: \(detail)"
            case .noPlayableStreams: return "The stream contained no video or audio."
            case .openOutput(let detail): return "Couldn't create the file: \(detail)"
            case .writeFailed(let detail): return "Writing failed: \(detail)"
            case .cancelled: return "Download cancelled."
            }
        }
    }

    /// Containers tried in order. MP4 is what a download should be; Matroska
    /// is a last resort for a codec the MP4 muxer has no tag for, so that an
    /// exotic broadcast stream produces a playable file instead of nothing.
    /// Everything seen so far — including the MPEG-2 audio common on European
    /// DVB feeds — goes into MP4 happily.
    private static let containers: [(format: String, ext: String)] = [
        ("mp4", "mp4"),
        ("matroska", "mkv")
    ]

    private let lock = NSLock()
    private var isCancelled = false

    /// How often progress is reported back. Fine-grained enough for a smooth
    /// progress bar, coarse enough not to hop to the main actor per packet.
    private static let progressInterval: TimeInterval = 0.5

    private let queue = DispatchQueue(label: "com.nexuspvr.remux", qos: .utility)

    /// Aborts a running job. Safe to call from any thread, including while
    /// `av_read_frame` is blocked on the network.
    func cancel() {
        lock.lock()
        isCancelled = true
        lock.unlock()
    }

    private var cancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancelled
    }

    /// Remuxes `input` into `outputDirectory/<baseName>.<ext>`.
    ///
    /// - Parameters:
    ///   - input: the stream URL. Any protocol libavformat understands; in
    ///     practice `http(s)`.
    ///   - headers: auth headers, e.g. `DispatcherClient.streamAuthHeaders()`.
    ///   - stopAfterSeconds: stop once this much programme has been written.
    ///     `nil` runs to the end of the stream. Required for catch-up, whose
    ///     archive extends far past the programme — see `DownloadPolicy`.
    ///   - onProgress: called on an arbitrary queue at most twice a second.
    func run(
        input: URL,
        headers: [String: String],
        outputDirectory: URL,
        baseName: String,
        stopAfterSeconds: Double?,
        onProgress: @escaping @Sendable (Double, Int64) -> Void
    ) async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                var lastError: Error = RemuxError.noPlayableStreams
                for container in Self.containers {
                    let output = outputDirectory.appendingPathComponent("\(baseName).\(container.ext)")
                    do {
                        let result = try self.remux(
                            input: input,
                            headers: headers,
                            output: output,
                            containerFormat: container.format,
                            stopAfterSeconds: stopAfterSeconds,
                            onProgress: onProgress
                        )
                        continuation.resume(returning: result)
                        return
                    } catch {
                        try? FileManager.default.removeItem(at: output)
                        lastError = error
                        // Only a muxer rejecting the codec set is worth
                        // retrying in another container; a dead network or a
                        // cancelled job would fail exactly the same way twice.
                        guard case RemuxError.openOutput = error else { break }
                    }
                }
                continuation.resume(throwing: lastError)
            }
        }
    }

    // MARK: - The blocking job

    private func remux(
        input: URL,
        headers: [String: String],
        output: URL,
        containerFormat: String,
        stopAfterSeconds: Double?,
        onProgress: @escaping @Sendable (Double, Int64) -> Void
    ) throws -> Result {
        // Cancelled before the first byte: bail out with the right error rather
        // than letting the interrupt callback surface as an open failure.
        if cancelled { throw RemuxError.cancelled }

        var inputContext = avformat_alloc_context()
        guard inputContext != nil else { throw RemuxError.openInput("out of memory") }

        // The interrupt callback is libavformat's only cancellation point: it
        // is polled from inside blocking reads, and returning non-zero unwinds
        // them. `self` outlives the job, which is what makes the unretained
        // pointer safe.
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        inputContext?.pointee.interrupt_callback = AVIOInterruptCB(
            callback: { opaque in
                guard let opaque else { return 0 }
                let remuxer = Unmanaged<MediaRemuxer>.fromOpaque(opaque).takeUnretainedValue()
                return remuxer.cancelled ? 1 : 0
            },
            opaque: selfPointer
        )

        var options: OpaquePointer?
        defer { av_dict_free(&options) }
        if !headers.isEmpty {
            let joined = headers.map { "\($0.key): \($0.value)\r\n" }.joined()
            av_dict_set(&options, "headers", joined, 0)
        }
        // Same resilience the player asks of mpv (`stream-lavf-o` in
        // MPVPlayerCore): survive a dropped connection mid-programme rather
        // than losing a half-hour download to one blip.
        av_dict_set(&options, "reconnect", "1", 0)
        av_dict_set(&options, "reconnect_streamed", "1", 0)
        av_dict_set(&options, "reconnect_delay_max", "3", 0)
        av_dict_set(&options, "rw_timeout", "30000000", 0)

        var status = avformat_open_input(&inputContext, input.absoluteString, nil, &options)
        guard status >= 0, let inputContext else {
            throw RemuxError.openInput(Self.message(for: status))
        }
        defer {
            var context: UnsafeMutablePointer<AVFormatContext>? = inputContext
            avformat_close_input(&context)
        }

        status = avformat_find_stream_info(inputContext, nil)
        guard status >= 0 else { throw RemuxError.openInput(Self.message(for: status)) }

        var outputContext: UnsafeMutablePointer<AVFormatContext>?
        status = avformat_alloc_output_context2(&outputContext, nil, containerFormat, output.path)
        guard status >= 0, let outputContext else {
            throw RemuxError.openOutput(Self.message(for: status))
        }
        var didWriteHeader = false
        defer {
            if didWriteHeader { av_write_trailer(outputContext) }
            if let format = outputContext.pointee.oformat,
               format.pointee.flags & AVFMT_NOFILE == 0 {
                avio_closep(&outputContext.pointee.pb)
            }
            var context: UnsafeMutablePointer<AVFormatContext>? = outputContext
            avformat_free_context(context)
            context = nil
        }

        // Map the first video stream and every audio stream. Data, subtitle and
        // secondary video streams from a broadcast TS mux (teletext, DVB subs)
        // have no MP4 equivalent and would only fail the header write.
        var streamMap: [Int: Int32] = [:]
        var hasVideo = false
        for index in 0..<Int(inputContext.pointee.nb_streams) {
            guard let inputStream = inputContext.pointee.streams[index] else { continue }
            let type = inputStream.pointee.codecpar.pointee.codec_type
            if type == AVMEDIA_TYPE_VIDEO {
                if hasVideo { continue }
                hasVideo = true
            } else if type != AVMEDIA_TYPE_AUDIO {
                continue
            }

            guard let outputStream = avformat_new_stream(outputContext, nil) else {
                throw RemuxError.openOutput("could not allocate output stream")
            }
            status = avcodec_parameters_copy(outputStream.pointee.codecpar, inputStream.pointee.codecpar)
            guard status >= 0 else { throw RemuxError.openOutput(Self.message(for: status)) }
            // The input tag is the TS one; letting the muxer pick its own is
            // what makes the copy land in the container correctly.
            outputStream.pointee.codecpar.pointee.codec_tag = 0
            streamMap[index] = outputStream.pointee.index
        }
        guard !streamMap.isEmpty else { throw RemuxError.noPlayableStreams }

        if let format = outputContext.pointee.oformat, format.pointee.flags & AVFMT_NOFILE == 0 {
            status = avio_open(&outputContext.pointee.pb, output.path, AVIO_FLAG_WRITE)
            guard status >= 0 else { throw RemuxError.openOutput(Self.message(for: status)) }
        }

        var headerOptions: OpaquePointer?
        defer { av_dict_free(&headerOptions) }
        if containerFormat == "mp4" {
            // Move the index to the front so the file is seekable from the
            // first byte — it is written to a local disk, so the extra pass at
            // trailer time is cheap.
            av_dict_set(&headerOptions, "movflags", "+faststart", 0)
        }
        status = avformat_write_header(outputContext, &headerOptions)
        guard status >= 0 else { throw RemuxError.openOutput(Self.message(for: status)) }
        didWriteHeader = true

        // MARK: Packet loop

        guard let packet = av_packet_alloc() else {
            throw RemuxError.writeFailed("out of memory")
        }
        defer {
            var owned: UnsafeMutablePointer<AVPacket>? = packet
            av_packet_free(&owned)
        }

        /// One timeline per stream, rebasing timestamps and absorbing the
        /// discontinuities a broadcast recording is full of. Created lazily
        /// because the anchor is the first timestamp seen anywhere in the file
        /// — shared by every stream so audio stays in sync with video.
        var timelines: [Int: PacketTimeline] = [:]
        /// Last decode timestamp written per output stream, in the output's own
        /// ticks — the units the muxer's monotonicity check uses.
        var lastWrittenDts: [Int32: Int64] = [:]
        var anchorSeconds: Double?
        var writtenSeconds: Double = 0
        var writtenBytes: Int64 = 0
        var lastReport = Date.distantPast

        while true {
            if cancelled { throw RemuxError.cancelled }

            status = av_read_frame(inputContext, packet)
            if status < 0 { break } // end of stream, or the interrupt fired

            defer { av_packet_unref(packet) }

            let inputIndex = Int(packet.pointee.stream_index)
            guard let outputIndex = streamMap[inputIndex],
                  let inputStream = inputContext.pointee.streams[inputIndex],
                  let outputStream = outputContext.pointee.streams[Int(outputIndex)] else {
                continue
            }

            let inputTimeBase = inputStream.pointee.time_base
            let outputTimeBase = outputStream.pointee.time_base
            let secondsPerTick = av_q2d(inputTimeBase)

            let pts = packet.pointee.pts != Self.noTimestamp ? packet.pointee.pts : nil
            let dts = packet.pointee.dts != Self.noTimestamp ? packet.pointee.dts : nil

            if anchorSeconds == nil, let reference = dts ?? pts {
                anchorSeconds = Double(reference) * secondsPerTick
            }
            if timelines[inputIndex] == nil {
                let anchorTicks = Int64((anchorSeconds ?? 0) / secondsPerTick)
                timelines[inputIndex] = PacketTimeline(secondsPerTick: secondsPerTick, anchor: anchorTicks)
            }
            // A packet that can't be placed at all (no timestamps, nothing
            // written yet to carry on from) is dropped rather than handed to a
            // muxer that would reject it.
            guard let normalized = timelines[inputIndex]?.normalize(
                pts: pts,
                dts: dts,
                duration: packet.pointee.duration
            ) else { continue }

            let rescaled = PacketTimeline.enforcingIncrease(
                pts: av_rescale_q_rnd(normalized.pts, inputTimeBase, outputTimeBase, Self.rounding),
                dts: av_rescale_q_rnd(normalized.dts, inputTimeBase, outputTimeBase, Self.rounding),
                after: lastWrittenDts[outputIndex]
            )
            lastWrittenDts[outputIndex] = rescaled.dts

            packet.pointee.stream_index = outputIndex
            packet.pointee.pts = rescaled.pts
            packet.pointee.dts = rescaled.dts
            packet.pointee.duration = av_rescale_q(packet.pointee.duration, inputTimeBase, outputTimeBase)
            packet.pointee.pos = -1

            // Read what we need before writing: `av_interleaved_write_frame`
            // takes the packet's reference and leaves it blank.
            let size = Int64(packet.pointee.size)
            let presentation = rescaled.pts

            status = av_interleaved_write_frame(outputContext, packet)
            guard status >= 0 else {
                // Include what the muxer choked on: which stream, and the
                // timestamps it was handed. Without that, "Invalid argument" is
                // unactionable.
                throw RemuxError.writeFailed(
                    "\(Self.message(for: status)) [stream \(outputIndex), pts \(rescaled.pts), dts \(rescaled.dts)]"
                )
            }
            writtenBytes += size

            if presentation != Self.noTimestamp {
                let seconds = Double(presentation) * av_q2d(outputTimeBase)
                if seconds > writtenSeconds { writtenSeconds = seconds }
            }

            if DownloadPolicy.shouldStop(writtenSeconds: writtenSeconds, expectedDuration: stopAfterSeconds) {
                break
            }

            let now = Date()
            if now.timeIntervalSince(lastReport) >= Self.progressInterval {
                lastReport = now
                onProgress(writtenSeconds, writtenBytes)
            }
        }

        if cancelled { throw RemuxError.cancelled }

        onProgress(writtenSeconds, writtenBytes)
        return Result(url: output, seconds: writtenSeconds, bytes: writtenBytes)
    }

    // MARK: - Helpers

    /// `AV_NOPTS_VALUE` is a macro, so it doesn't reach Swift. It is
    /// `0x8000000000000000` reinterpreted as a signed 64-bit integer.
    private static let noTimestamp = Int64.min

    private static let rounding = AVRounding(
        rawValue: AV_ROUND_NEAR_INF.rawValue | AV_ROUND_PASS_MINMAX.rawValue
    )

    /// `av_err2str` is a macro, so Swift has to call the underlying function.
    private static func message(for code: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        guard av_strerror(code, &buffer, buffer.count) == 0 else {
            return "error \(code)"
        }
        return String(cString: buffer)
    }
}
