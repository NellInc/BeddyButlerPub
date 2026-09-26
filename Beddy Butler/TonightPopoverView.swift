import Foundation
import SwiftUI

@MainActor
struct TonightPopoverView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var scheduler: ButlerTimer

    let openPreferences: () -> Void
    let openAbout: () -> Void
    let preview: () -> Void
    let acknowledge: () -> Void
    let snooze: () -> Void
    let togglePause: () -> Void
    let pauseTonight: () -> Void
    let quit: () -> Void

    var body: some View {
        ZStack {
            BeddyBackdrop()

            VStack(alignment: .leading, spacing: 18) {
                panelHeader
                nextNudgeCard
                scheduleSummary
                if scheduler.hasFinishedTonight {
                    Button {
                        scheduler.undoFinishTonight()
                    } label: {
                        Text("Undo finish")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BeddySecondaryButtonStyle())
                    .accessibilityIdentifier("popover.undoFinish")
                    .help("Resume reminders and restore any waiting menu bar badge.")
                }
                if scheduler.visualNudgePending {
                    Text(
                        settings.isMuted()
                            ? "Reminders paused until \(settings.mutedUntil.map { LocalizedScheduleText.dayAndTime($0) } ?? "the next window")"
                            : "Next nudge: \(scheduler.nextNudge.map { LocalizedScheduleText.dayAndTime($0) } ?? "none scheduled")"
                    )
                    .font(.callout)
                    .foregroundStyle(BeddyPalette.muted)
                }

                if scheduler.visualNudgePending {
                    Button {
                        acknowledge()
                    } label: {
                        Label("Acknowledge Badge", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BeddyPrimaryButtonStyle(glow: BeddyPalette.blue))
                    .accessibilityIdentifier("popover.acknowledge")
                }

                if !scheduler.hasFinishedTonight { actionGrid }
                progressionFooter
                utilityFooter
            }
            .padding(24)
        }
        .frame(width: 420)
        .foregroundStyle(BeddyPalette.ink)
        .tint(BeddyPalette.blue)
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Beddy Butler Tonight panel")
    }

    private var panelHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("TONIGHT")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(BeddyPalette.blue)
                Text(panelTitle)
                    .font(.system(size: 21, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(BeddyPalette.ink)
                    .accessibilityAddTraits(.isHeader)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: statusColor, radius: 4)
                Text(statusTitle)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(statusTextColor)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(statusColor.opacity(0.12), in: Capsule())
            .accessibilityLabel("Status: \(statusTitle)")
        }
    }

    private var nextNudgeCard: some View {
        HStack(spacing: 15) {
            ZStack {
                LinearGradient(
                    colors: [BeddyPalette.blueBright, Color(red: 100 / 255, green: 143 / 255, blue: 228 / 255)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: nextCardSymbol)
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(Color(red: 16 / 255, green: 37 / 255, blue: 66 / 255))
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .shadow(color: BeddyPalette.blue.opacity(0.27), radius: 13, y: 7)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(nextCardEyebrow)
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Color(red: 145 / 255, green: 170 / 255, blue: 200 / 255))
                Text(nextCardValue)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .tracking(-0.7)
                    .foregroundStyle(BeddyPalette.ink)
                if let date = nextCardDate {
                    Text(LocalizedScheduleText.dayLabel(date))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(BeddyPalette.muted)
                }
                let detail = nextCardDetail
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(BeddyPalette.muted)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(17)
        .background {
            LinearGradient(
                colors: [BeddyPalette.blue.opacity(0.18), Color.white.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var scheduleSummary: some View {
        let presentation = schedulePresentation
        let name = presentation?.name ?? settings.primaryScheduleName
        let times = presentation.map {
            (LocalizedScheduleText.time($0.window.start), LocalizedScheduleText.time($0.window.end))
        }
        let windowText = times.map { "\($0.0)  →  \($0.1)" } ?? "No active nights"
        let spokenWindow = times.map { "\($0.0) to \($0.1)" } ?? "No active nights"

        return HStack(spacing: 14) {
            Text(name)
                .foregroundStyle(BeddyPalette.muted)
            Spacer(minLength: 8)
            Text(windowText)
                .fontWeight(.semibold)
                .foregroundStyle(Color(red: 219 / 255, green: 232 / 255, blue: 248 / 255))
                .monospacedDigit()
        }
        .font(.system(size: 13))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(spokenWindow)")
    }

    private var actionGrid: some View {
        VStack(spacing: 9) {
            HStack(spacing: 9) {
                Button {
                    preview()
                } label: {
                    Label(previewButtonLabel, systemImage: previewButtonSymbol)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BeddySecondaryButtonStyle())
                .accessibilityLabel(previewButtonAccessibilityLabel)
                .accessibilityIdentifier("popover.preview")

                Button {
                    snooze()
                } label: {
                    Label("Snooze \(settings.snoozeMinutes) min", systemImage: "timer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BeddySecondaryButtonStyle())
                .disabled(!scheduler.canSnooze)
                .help(
                    "Available during the bedtime window. Snooze stops at bedtime if the chosen duration would run past it."
                )
                .accessibilityIdentifier("popover.snooze")
            }

            if scheduler.canSnooze || scheduler.isSnoozed {
                // Acknowledge Badge is the primary action while a badge waits, so this steps back.
                if scheduler.visualNudgePending {
                    finishTonightButton.buttonStyle(BeddySecondaryButtonStyle())
                } else {
                    finishTonightButton.buttonStyle(BeddyPrimaryButtonStyle(glow: BeddyPalette.blue))
                }
            }

            if !scheduler.hasFinishedTonight {
                Button {
                    togglePause()
                } label: {
                    Label(
                        settings.isMuted() ? "Resume nudges" : "Pause tonight",
                        systemImage: settings.isMuted() ? "play.circle.fill" : "pause.circle"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 8)
                .foregroundStyle(BeddyPalette.muted)
                .accessibilityIdentifier("popover.pause")
                .disabled(!settings.hasActivatedSchedule)
            }

            if scheduler.isSnoozed {
                Button {
                    pauseTonight()
                } label: {
                    Label("Pause tonight", systemImage: "pause.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 8)
                .foregroundStyle(BeddyPalette.muted)
                .accessibilityIdentifier("popover.pauseTonight")
            }
        }
    }

    private var finishTonightButton: some View {
        Button {
            scheduler.finishTonight()
        } label: {
            Text("I’m heading to bed")
                .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("popover.finishTonight")
        .help(
            "Clear reminders and pause tonight."
        )
    }

    private var progressionFooter: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(footerModeTitle)
                .foregroundStyle(BeddyPalette.muted)
            Spacer(minLength: 8)
            Text(footerModeDetail)
                .fontWeight(.semibold)
                .foregroundStyle(BeddyPalette.blue)
        }
        .font(.system(size: 12))
        .padding(.top, 16)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.09))
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var utilityFooter: some View {
        HStack {
            Button("Preferences…") {
                openPreferences()
            }
            .keyboardShortcut(",")
            .accessibilityIdentifier("popover.preferences")

            Spacer()

            Button("About") {
                openAbout()
            }
            .accessibilityLabel("About Beddy Butler")
            .accessibilityIdentifier("popover.about")

            Spacer()

            Button("Quit") {
                quit()
            }
            .accessibilityIdentifier("popover.quit")
        }
        .buttonStyle(.plain)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(BeddyPalette.muted)
    }

    private var panelTitle: String {
        if !settings.hasActivatedSchedule { return "Welcome to the night shift" }
        if scheduler.hasFinishedTonight { return "Good night." }
        if scheduler.visualNudgePending {
            return "A nudge is waiting"
        }
        if settings.isMuted() {
            return "Rest easy for now"
        }
        return scheduler.nextNudge == nil ? "Evening at ease" : "Wind down gently"
    }

    private var statusTitle: String {
        if !settings.hasActivatedSchedule { return "Awaiting setup" }
        if scheduler.hasFinishedTonight { return "Finished" }
        if scheduler.visualNudgePending { return "Waiting" }
        if settings.isMuted() { return "Paused" }
        return scheduler.nextNudge == nil ? "At ease" : "On duty"
    }

    private var statusColor: Color {
        if !settings.hasActivatedSchedule { return BeddyPalette.faint }
        if scheduler.hasFinishedTonight { return BeddyPalette.violet }
        if scheduler.visualNudgePending || settings.isMuted() { return BeddyPalette.warm }
        return scheduler.nextNudge == nil ? BeddyPalette.faint : BeddyPalette.success
    }

    /// Faint stays on the dot and capsule but is too low in contrast for the status text.
    private var statusTextColor: Color {
        statusColor == BeddyPalette.faint ? BeddyPalette.muted : statusColor
    }

    private var nextCardEyebrow: String {
        if scheduler.visualNudgePending { return "NUDGE WAITING" }
        if scheduler.hasFinishedTonight { return "NEXT REMINDER" }
        if settings.isMuted() { return "PAUSED UNTIL" }
        return "NEXT NUDGE"
    }

    private var nextCardDate: Date? {
        if scheduler.visualNudgePending { return nil }
        if scheduler.hasFinishedTonight { return scheduler.nextNudge }
        if settings.isMuted() { return settings.mutedUntil }
        return scheduler.nextNudge
    }

    private var nextCardValue: String {
        if !settings.hasActivatedSchedule { return "Not started" }
        if scheduler.visualNudgePending {
            return scheduler.pendingVisualNudgeCount == 1
                ? "Ready"
                : "\(scheduler.pendingVisualNudgeCount) waiting"
        }
        if let date = nextCardDate { return LocalizedScheduleText.time(date) }
        return "No plans"
    }

    private var nextCardDetail: String {
        if !settings.hasActivatedSchedule { return "Complete setup in Preferences." }
        if scheduler.hasFinishedTonight {
            return scheduler.nextNudge == nil ? "No further reminders scheduled" : ""
        }
        if scheduler.visualNudgePending {
            return "A persistent badge is waiting for you"
        }
        if settings.isMuted() {
            return "Tonight’s reminders are taking a break"
        }
        switch settings.nudgeDelivery {
        case .sound:
            return "\(scheduler.nextPersonality.title) Butler · Sound"
        case .visual:
            return "Persistent visual badge"
        case .both:
            return "\(scheduler.nextPersonality.title) Butler · Sound + badge"
        }
    }

    private var nextCardSymbol: String {
        if scheduler.visualNudgePending { return "bell.badge.fill" }
        if scheduler.hasFinishedTonight { return "moon.zzz.fill" }
        if settings.isMuted() { return "pause.fill" }
        return "moon.zzz.fill"
    }

    private var previewButtonLabel: String {
        switch settings.nudgeDelivery {
        case .sound: "Hear sample"
        case .visual: "Preview badge"
        case .both: "Preview both"
        }
    }

    private var previewButtonAccessibilityLabel: String {
        settings.nudgeDelivery == .both ? "Preview sound and badge" : previewButtonLabel
    }

    private var previewButtonSymbol: String {
        settings.nudgeDelivery.includesSound ? "play.fill" : "bell.badge.fill"
    }

    private var footerModeTitle: String {
        if settings.nudgeDelivery == .visual { return "Visual mode" }
        return settings.progressiveMode ? "Gradually firmer" : "Steady mode"
    }

    private var footerModeDetail: String {
        if settings.nudgeDelivery == .visual { return "Persistent badge" }
        return settings.progressiveMode
            ? "\(settings.personality.title) to \(settings.effectiveMaximumPersonality.title)"
            : settings.personality.title
    }

    private var weeklySchedule: WeeklyBedtimeSchedule { settings.weeklySchedule }

    private var schedulePresentation: (name: String, window: BedtimeWindow)? {
        let calendar = Calendar.autoupdatingCurrent
        let schedule = weeklySchedule
        guard
            let window = ScheduleCalculator(calendar: calendar).window(
                containingOrAfter: Date(),
                schedule: schedule
            ),
            let selection = schedule.selection(for: window.start, calendar: calendar)
        else {
            return nil
        }

        let name =
            switch selection {
            case .primary: settings.primaryScheduleName
            case .alternate: settings.alternateScheduleName
            case .oneNightOverride: "Tonight’s adjustment"
            }
        return (name, window)
    }

}
