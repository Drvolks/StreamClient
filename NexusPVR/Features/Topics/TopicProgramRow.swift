//
//  TopicProgramRow.swift
//  nextpvr-apple-client
//
//  Row displaying a program matching a topic keyword
//

import SwiftUI

// MARK: - Program Glyph

/// The round TV glyph that leads a topic program row.
struct ProgramGlyph: View {
    var size: CGFloat = 56
    var iconSize: CGFloat = 22

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.surfaceElevated)
            Image(systemName: "tv")
                .font(.system(size: iconSize))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Recording Status Badge

struct RecordingStatusBadge: View {
    let isProcessing: Bool
    let isRecording: Bool
    let isScheduled: Bool

    var body: some View {
        HStack(spacing: 4) {
            if isProcessing {
                ProgressView()
                    .scaleEffect(0.8)
            } else if isRecording {
                Image(systemName: "record.circle")
                    .foregroundStyle(Theme.recording)
                Text("Recording")
                    .font(.caption)
                    .foregroundStyle(Theme.recording)
            } else if isScheduled {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.success)
                Text("Scheduled")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityIdentifier("scheduled-indicator")
            } else {
                Image(systemName: "record.circle")
                    .foregroundStyle(Theme.accent)
                Text("Record")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, Theme.spacingSM)
        .padding(.vertical, Theme.spacingXS)
        .background(isRecording ? Theme.recording.opacity(0.1) : isScheduled ? Theme.success.opacity(0.1) : Theme.accent.opacity(0.1))
        .clipShape(Capsule())
    }
}

// MARK: - Existing Recording Info

struct ExistingRecordingInfo: View {
    let existingRecording: Recording?
    let earlierScheduled: Recording?

    var body: some View {
        if let existing = existingRecording {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle")
                Text("Already recorded \(existing.startDate ?? Date(), style: .time)")
            }
            .font(.caption)
            .foregroundStyle(Theme.warning)
        } else if let earlier = earlierScheduled {
            HStack(spacing: 4) {
                Image(systemName: "clock.badge.checkmark")
                Text("Scheduled \(earlier.startDate ?? Date(), style: .time)")
            }
            .font(.caption)
            .foregroundStyle(Theme.success)
        }
    }
}

// MARK: - iOS/macOS Row

struct TopicProgramRow: View {
    @EnvironmentObject private var client: PVRClient
    @EnvironmentObject private var appState: AppState

    let program: Program
    let channel: Channel
    let matchedKeyword: String
    var onRecordingChanged: (() -> Void)? = nil
    var onShowDetails: ((Int?, Recording?) -> Void)? = nil

    @StateObject private var vm: TopicProgramRowViewModel

    init(program: Program, channel: Channel, matchedKeyword: String,
         onRecordingChanged: (() -> Void)? = nil,
         onShowDetails: ((Int?, Recording?) -> Void)? = nil) {
        self.program = program
        self.channel = channel
        self.matchedKeyword = matchedKeyword
        self.onRecordingChanged = onRecordingChanged
        self.onShowDetails = onShowDetails
        _vm = StateObject(wrappedValue: TopicProgramRowViewModel(program: program, channel: channel))
    }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.spacingMD) {
            ProgramGlyph()

            VStack(alignment: .leading, spacing: Theme.spacingXS) {
                if program.isCurrentlyAiring {
                    Label("Live", systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                }

                HStack(alignment: .top, spacing: 6) {
                    Text(program.cleanName)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    Spacer()
                    if program.shouldShowLiveBadge { LiveBadge() }
                    if program.shouldShowNewBadge { NewBadge() }
                }

                HStack {
                    Text(channel.name)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)

                    Spacer()

                    if !program.hasEnded && appState.showsRecordings {
                        Button {
                            vm.toggleRecording(using: client, onChanged: onRecordingChanged)
                        } label: {
                            RecordingStatusBadge(
                                isProcessing: vm.isProcessing,
                                isRecording: vm.isRecording,
                                isScheduled: vm.isScheduled
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(vm.isProcessing)
                    }
                }

                HStack {
                    Text(vm.programScheduleText)
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)

                    Spacer()

                    ExistingRecordingInfo(
                        existingRecording: vm.existingRecording,
                        earlierScheduled: vm.earlierScheduled
                    )
                }
            }
        }
        .padding(.vertical, Theme.spacingSM)
        .contentShape(Rectangle())
        .accessibilityIdentifier("topic-program-\(program.id)")
        #if !os(tvOS)
        .onTapGesture {
            onShowDetails?(vm.existingRecordingId, vm.existingRecording)
        }
        #endif
        .task {
            if appState.showsRecordings {
                await vm.checkIfScheduled(using: client)
            }
        }
    }
}

// MARK: - tvOS Row

#Preview {
    List {
        TopicProgramRow(
            program: .preview,
            channel: Channel(id: 1, name: "ABC", number: 7),
            matchedKeyword: "Sports"
        )
        .listRowBackground(Theme.surface)
    }
    .listStyle(.plain)
    .background(Theme.background)
    .preferredColorScheme(.dark)
}
