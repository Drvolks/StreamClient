//
//  EventLogRow.swift
//  PVR Client
//
//  One row of the Event Log: a request, or a playback session.
//

import SwiftUI

struct EventLogRow: View {
    let event: NetworkEvent
    /// The playback session this row stands for, if it is one.
    let session: PlaybackSession?
    /// Shows the full error detail instead of the first lines.
    var isExpanded = false

    var body: some View {
        if let session {
            sessionBody(session)
        } else {
            requestBody
        }
    }

    // MARK: - Playback session

    private func sessionBody(_ session: PlaybackSession) -> some View {
        HStack(alignment: .top, spacing: Theme.spacingSM) {
            Image(systemName: session.hasProblems ? "exclamationmark.triangle.fill" : "play.rectangle.fill")
                .foregroundStyle(session.hasProblems ? Theme.error : Theme.accent)
                .font(.caption)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(event.timestamp, format: .dateTime.hour().minute().second())
                        .foregroundStyle(Theme.textTertiary)
                    Text("Playback")
                        .foregroundStyle(Theme.textPrimary)
                        .fontWeight(.semibold)
                    Spacer()
                    Text(statusLabel(session))
                        .foregroundStyle(statusColor(session))
                        .fontWeight(.medium)
                }
                .font(.caption)
                Text(session.title)
                    .foregroundStyle(Theme.textSecondary)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let host = session.host {
                    Text(host)
                        .foregroundStyle(Theme.textTertiary)
                        .font(.caption2)
                        .lineLimit(1)
                        .accessibilityLabel("Host \(host)")
                }
                Text(summary(session))
                    .foregroundStyle(session.hasProblems ? Theme.error : Theme.textTertiary)
                    .font(.caption2)
                    .lineLimit(isExpanded ? nil : 2)
            }
            #if os(tvOS)
            Image(systemName: "chevron.right")
                .foregroundStyle(Theme.textTertiary)
                .font(.caption)
            #endif
        }
        .accessibilityElement(children: .combine)
    }

    private func statusLabel(_ session: PlaybackSession) -> String {
        switch session.outcome {
        case .inProgress: return session.errorCount > 0 ? "Playing, errors" : "Playing"
        case .ended: return session.errorCount > 0 ? "Ended, errors" : "Ended"
        case .failed: return "Failed"
        }
    }

    private func statusColor(_ session: PlaybackSession) -> Color {
        if session.hasProblems { return Theme.error }
        if case .inProgress = session.outcome { return Theme.success }
        return Theme.textSecondary
    }

    private func summary(_ session: PlaybackSession) -> String {
        var parts = [EventLogExporter.formatDuration(session.duration())]
        if case .failed(let reason) = session.outcome { parts.append(reason) }
        if session.errorCount > 0 { parts.append(count(session.errorCount, "error")) }
        if session.warningCount > 0 { parts.append(count(session.warningCount, "warning")) }
        parts.append(count(session.lines.count + session.omittedLineCount, "line"))
        return parts.joined(separator: " · ")
    }

    private func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }

    // MARK: - Request

    private var requestBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(event.timestamp, format: .dateTime.hour().minute().second())
                    .foregroundStyle(Theme.textTertiary)
                    .font(.caption)
                Text(event.method)
                    .foregroundStyle(Theme.textSecondary)
                    .font(.caption)
                    .fontWeight(.medium)
                Text(event.path)
                    .foregroundStyle(event.isSuccess ? Theme.textPrimary : Theme.error)
                    .font(.caption)
                    .lineLimit(isExpanded ? nil : 1)
                Spacer()
                if let code = event.statusCode {
                    Text("\(code)")
                        .foregroundStyle(event.isSuccess ? Theme.success : Theme.error)
                        .font(.caption)
                        .fontWeight(.medium)
                } else if !event.isSuccess {
                    Text("ERR")
                        .foregroundStyle(Theme.error)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                if event.durationMs > 0 {
                    Text("\(event.durationMs)ms")
                        .foregroundStyle(Theme.textTertiary)
                        .font(.caption)
                }
            }
            if let host = event.host {
                Text(host)
                    .foregroundStyle(Theme.textTertiary)
                    .font(.caption2)
                    .lineLimit(1)
                    .accessibilityLabel("Host \(host)")
            }
            if let detail = event.errorDetail {
                Text(detail)
                    .foregroundStyle(event.isSuccess ? Theme.textSecondary : Theme.error)
                    .font(.caption2)
                    .lineLimit(isExpanded ? nil : 3)
            }
        }
    }
}
