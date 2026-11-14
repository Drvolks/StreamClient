//
//  PlaybackSessionDetailView.swift
//  PVR Client
//
//  Everything one playback session logged.
//

import SwiftUI

struct PlaybackSessionDetailView: View {
    let session: PlaybackSession
    #if os(tvOS)
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var shareRequest: LogShareRequest?
    /// Lines per focusable block: the remote scrolls by moving focus, and one
    /// stop per line would make a 600-line log very slow to get through.
    private static let linesPerBlock = 6
    #endif

    var body: some View {
        #if os(tvOS)
        tvBody
        #else
        listBody
        #endif
    }

    private var summaryRows: [(String, String)] {
        var rows: [(String, String)] = [
            ("Stream", session.title),
            ("Started", session.startedAt.formatted(date: .abbreviated, time: .standard)),
            ("Duration", EventLogExporter.formatDuration(session.duration())),
            ("Outcome", session.outcome.summary),
            ("Errors", "\(session.errorCount)"),
            ("Warnings", "\(session.warningCount)"),
        ]
        if let host = session.host { rows.insert(("Host", host), at: 1) }
        if session.omittedLineCount > 0 {
            rows.append(("Omitted", "\(session.omittedLineCount) lines"))
        }
        return rows
    }

    /// The lines, with a marker where lines were dropped to respect the cap.
    private var items: [PlaybackLogItem] {
        var result: [PlaybackLogItem] = []
        for (index, line) in session.lines.enumerated() {
            if index == session.omissionIndex {
                result.append(.omission(session.omittedLineCount))
            }
            result.append(.line(line))
        }
        if session.omissionIndex == session.lines.count {
            result.append(.omission(session.omittedLineCount))
        }
        return result
    }

    #if !os(tvOS)
    private var listBody: some View {
        List {
            Section("Summary") {
                ForEach(summaryRows, id: \.0) { row in
                    LabeledContent(row.0) {
                        Text(row.1)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }
                    .font(.callout)
                }
            }
            Section("Log") {
                ForEach(items) { item in
                    itemView(item)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle("Playback")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                ShareLink(
                    item: EventLogExportFile.session(session),
                    preview: SharePreview("Playback Session")
                ) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
    }
    #endif

    @ViewBuilder
    private func itemView(_ item: PlaybackLogItem) -> some View {
        switch item {
        case .line(let line):
            PlaybackLogLineView(line: line)
                #if !os(tvOS)
                .textSelection(.enabled)
                #endif
        case .omission(let count):
            Text("… \(count) lines omitted …")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    #if os(tvOS)
    private var tvBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.spacingSM) {
                HStack(alignment: .center) {
                    Image(systemName: session.hasProblems ? "exclamationmark.triangle.fill" : "play.rectangle.fill")
                        .font(.title2)
                        .foregroundStyle(session.hasProblems ? Theme.error : Theme.accent)
                    Text("Playback Session")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Spacer()
                    Button {
                        shareRequest = LogShareRequest(
                            title: "Playback Session",
                            fileName: EventLogExporter.fileName(now: session.startedAt),
                            text: EventLogExporter.text(session: session)
                        )
                    } label: {
                        Label("Share", systemImage: "qrcode")
                    }
                }
                .focusSection()

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(summaryRows, id: \.0) { row in
                        HStack(alignment: .firstTextBaseline, spacing: Theme.spacingMD) {
                            Text(row.0)
                                .foregroundStyle(Theme.textTertiary)
                                .frame(width: 180, alignment: .leading)
                            Text(row.1)
                                .foregroundStyle(row.0 == "Outcome" && session.outcome.isFailure ? Theme.error : Theme.textPrimary)
                        }
                        .font(.caption)
                    }
                }
                .padding(.vertical, Theme.spacingSM)

                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    Button {} label: {
                        VStack(alignment: .leading, spacing: Theme.spacingSM) {
                            ForEach(block) { item in
                                itemView(item)
                            }
                        }
                    }
                    .buttonStyle(TVEventLogRowButtonStyle())
                }
            }
            .padding(.vertical)
            .padding(.horizontal, 40)
        }
        // A full-screen cover is transparent on tvOS: without a background
        // the Event Log underneath shows through.
        .background(MidnightGradients.ground(colorScheme).ignoresSafeArea())
        .onExitCommand { dismiss() }
        .fullScreenCover(item: $shareRequest) { request in
            TVLogShareView(request: request)
        }
    }

    private var blocks: [[PlaybackLogItem]] {
        let all = items
        return stride(from: 0, to: all.count, by: Self.linesPerBlock).map {
            Array(all[$0..<min($0 + Self.linesPerBlock, all.count)])
        }
    }
    #endif
}

/// A row of the session log: a line, or the marker for dropped lines.
private enum PlaybackLogItem: Identifiable {
    case line(PlaybackLogLine)
    case omission(Int)

    var id: String {
        switch self {
        case .line(let line): return line.id.uuidString
        case .omission: return "omission"
        }
    }
}
