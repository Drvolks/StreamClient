//
//  TopicProgramRow.swift
//  nextpvr-apple-client
//
//  A program matching a topic, in the iOS Topics list (Midnight): title and
//  badges, time and channel, description and any earlier-recording note,
//  with its state and a record button on the right. Tap opens the details.
//  What is on now gets the accent bar, as in the guide.
//

#if os(iOS)
import SwiftUI

struct TopicProgramRow: View {
    @EnvironmentObject private var client: PVRClient
    @EnvironmentObject private var appState: AppState

    let program: Program
    let channel: Channel
    var onRecordingChanged: (() -> Void)?
    var onShowDetails: ((Int?, Recording?) -> Void)?

    @StateObject private var vm: TopicProgramRowViewModel

    init(
        program: Program,
        channel: Channel,
        onRecordingChanged: (() -> Void)? = nil,
        onShowDetails: ((Int?, Recording?) -> Void)? = nil
    ) {
        self.program = program
        self.channel = channel
        self.onRecordingChanged = onRecordingChanged
        self.onShowDetails = onShowDetails
        _vm = StateObject(wrappedValue: TopicProgramRowViewModel(program: program, channel: channel))
    }

    private var canRecord: Bool {
        appState.showsRecordings && !program.hasEnded
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            details
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 8) {
                stateChip
                if canRecord { recordButton }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            if program.isCurrentlyAiring {
                Rectangle().fill(MidnightPalette.accentSoft).frame(width: 4)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(MidnightPalette.lineSoft).frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onShowDetails?(vm.existingRecordingId, vm.existingRecording)
        }
        .accessibilityIdentifier("topic-program-\(program.id)")
        .task {
            if appState.showsRecordings {
                await vm.checkIfScheduled(using: client)
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(program.cleanName)
                .font(.archivo(16, .extraBold))
                .foregroundStyle(MidnightPalette.ink)
                .lineLimit(2)

            Text("\(GuideCellTimeLabel.text(start: program.startDate, end: program.endDate, width: GuideCellTimeLabel.fullWidth)) · \(channel.name)")
                .midnightMeta(11)
                .foregroundStyle(MidnightPalette.inkSoft)
                .lineLimit(1)

            if program.shouldShowLiveBadge || program.shouldShowNewBadge {
                HStack(spacing: 5) {
                    if program.shouldShowLiveBadge { LiveBadge() }
                    if program.shouldShowNewBadge { NewBadge() }
                }
            }

            if let desc = description {
                Text(desc)
                    .font(.archivo(13))
                    .foregroundStyle(MidnightPalette.inkSoft)
                    .lineLimit(2)
            }

            if let note = earlierRecordingNote {
                Text(note)
                    .midnightMeta(10.5)
                    .foregroundStyle(MidnightPalette.inkFaint)
            }
        }
    }

    private var description: String? {
        [program.subtitle, program.desc]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    /// Says when this program was already recorded, or is set to record at
    /// an earlier airing, so the user can skip this one.
    private var earlierRecordingNote: String? {
        if let existing = vm.existingRecording, let start = existing.startDate {
            return "Already recorded · \(start.formatted(date: .abbreviated, time: .omitted)) \(GuideCellTimeLabel.time(start))"
        }
        if let earlier = vm.earlierScheduled, let start = earlier.startDate {
            return "Recording an earlier airing · \(start.formatted(date: .abbreviated, time: .omitted)) \(GuideCellTimeLabel.time(start))"
        }
        return nil
    }

    @ViewBuilder
    private var stateChip: some View {
        if vm.isRecording {
            Text("Recording")
                .badgeLabel()
                .foregroundStyle(.white)
                .background(Theme.recording, in: Theme.badgeShape)
        } else if vm.isScheduled {
            Text("Scheduled")
                .badgeLabel()
                .foregroundStyle(MidnightPalette.inkSoft)
                .overlay { Theme.badgeShape.strokeBorder(MidnightPalette.line, lineWidth: 1) }
                .accessibilityIdentifier("scheduled-indicator")
        } else if program.isCurrentlyAiring {
            MidnightFieldChip(text: "On now", size: 9)
        }
    }

    /// Records, or cancels the recording; a 44pt target on a 34pt box.
    private var recordButton: some View {
        let isSet = vm.isScheduled || vm.isRecording
        return Button {
            vm.toggleRecording(using: client, onChanged: onRecordingChanged)
        } label: {
            Group {
                if vm.isProcessing {
                    ProgressView()
                } else {
                    Image(systemName: isSet ? "record.circle.fill" : "record.circle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isSet ? Theme.recording : MidnightPalette.ink)
                }
            }
            .frame(width: 34, height: 34)
            .overlay { MidnightControlShape().strokeBorder(MidnightPalette.line, lineWidth: 1) }
            .frame(width: 44, height: 44, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(vm.isProcessing)
        .accessibilityLabel(isSet ? "Cancel recording" : "Record")
    }
}
#endif
