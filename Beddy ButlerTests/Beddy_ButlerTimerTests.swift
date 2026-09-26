import Combine
import Foundation
import XCTest

@testable import Beddy_Butler

@MainActor
private final class RecordingAudioPlayer: AudioPlaying {
    private(set) var playCount = 0
    private(set) var stopCount = 0
    private(set) var personalities: [ButlerPersonality] = []

    func play(_ personality: ButlerPersonality, volume: Double) throws -> URL {
        playCount += 1
        personalities.append(personality)
        // Mirrors the bundled clip names, which must never reach the interface.
        return URL(fileURLWithPath: "/tmp/Previewed 20151210 - Nell Watson - \(personality.title).18tuned.mp3")
    }

    func stop() {
        stopCount += 1
    }
}

@MainActor
private final class RecordingVisualNotifier: VisualNotificationDelivering {
    private(set) var deliveries: [(count: Int, personality: ButlerPersonality?)] = []
    private(set) var clearCount = 0

    func deliverVisualNudge(count: Int, personality: ButlerPersonality?) {
        deliveries.append((count, personality))
    }

    func clearVisualNudges() {
        clearCount += 1
    }
}

@MainActor
private final class TestClock {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }
}

final class BeddyButlerTimerTests: XCTestCase {
    @MainActor
    func testFreshInstallWaitsForStartBeforeSchedulingOrDelivering() throws {
        let defaults = makeIsolatedDefaults(prefix: "BeddyButler.SetupTests")
        let settings = AppSettings(defaults: defaults)
        let audio = RecordingAudioPlayer()
        let scheduler = ButlerTimer(settings: settings, audioPlayer: audio)
        defer { scheduler.timer?.invalidate() }
        XCTAssertFalse(settings.hasCompletedOnboarding)
        XCTAssertNil(scheduler.nextNudge)
        XCTAssertNil(scheduler.timer)
        settings.updateStartSeconds(21 * 3600)
        XCTAssertFalse(AppSettings(defaults: defaults).hasActivatedSchedule)
        XCTAssertNil(scheduler.nextNudge)
        XCTAssertFalse(scheduler.canSnooze)
        scheduler.snooze()
        scheduler.muteForCurrentWindow()
        scheduler.finishTonight()
        XCTAssertNil(settings.mutedUntil)
        scheduler.handleTimerFire()
        scheduler.deliverNudge()
        XCTAssertEqual(audio.playCount, 0)
        settings.completeOnboarding()
        XCTAssertFalse(scheduler.lastEvent.contains("Awaiting setup"))
        XCTAssertNotNil(scheduler.nextNudge)
        XCTAssertNotNil(scheduler.timer)
        settings.replayOnboarding()
        XCTAssertNotNil(scheduler.nextNudge)
        XCTAssertNotNil(scheduler.timer)
        XCTAssertTrue(AppSettings(defaults: defaults).hasActivatedSchedule)
    }

    private func calendar(timeZone identifier: String = "Europe/London") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        guard let timeZone = TimeZone(identifier: identifier) else {
            fatalError("Missing test time zone \(identifier)")
        }
        calendar.timeZone = timeZone
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int = 0,
        calendar: Calendar
    ) -> Date {
        guard
            let result = calendar.date(
                from: DateComponents(
                    year: year,
                    month: month,
                    day: day,
                    hour: hour,
                    minute: minute
                )
            )
        else {
            fatalError("Could not create test date")
        }
        return result
    }

    func testSchedulesAfterFutureWindowBegins() throws {
        let calendar = calendar()
        let now = date(2026, 7, 21, 20, calendar: calendar)
        let calculator = ScheduleCalculator(calendar: calendar)

        let nudge = try XCTUnwrap(
            calculator.nextNudge(
                after: now,
                interval: 10 * 60,
                startSeconds: 21 * 3_600 + 30 * 60,
                bedSeconds: 23 * 3_600
            ))

        XCTAssertEqual(
            calendar.dateComponents([.day, .hour, .minute], from: nudge.fireDate),
            DateComponents(day: 21, hour: 21, minute: 40)
        )
    }

    func testSchedulesFromNowInsideWindow() throws {
        let calendar = calendar()
        let now = date(2026, 7, 21, 22, calendar: calendar)
        let calculator = ScheduleCalculator(calendar: calendar)

        let nudge = try XCTUnwrap(
            calculator.nextNudge(
                after: now,
                interval: 10 * 60,
                startSeconds: 21 * 3_600 + 30 * 60,
                bedSeconds: 23 * 3_600
            ))

        XCTAssertEqual(nudge.fireDate, now.addingTimeInterval(10 * 60))
    }

    func testPastWindowMovesToTomorrow() throws {
        let calendar = calendar()
        let now = date(2026, 7, 21, 23, 10, calendar: calendar)
        let calculator = ScheduleCalculator(calendar: calendar)

        let nudge = try XCTUnwrap(
            calculator.nextNudge(
                after: now,
                interval: 10 * 60,
                startSeconds: 21 * 3_600 + 30 * 60,
                bedSeconds: 23 * 3_600
            ))

        XCTAssertEqual(
            calendar.dateComponents([.day, .hour, .minute], from: nudge.fireDate),
            DateComponents(day: 22, hour: 21, minute: 40)
        )
    }

    func testCrossMidnightWindowContainsEarlyMorning() throws {
        let calendar = calendar()
        let now = date(2026, 7, 22, 0, 30, calendar: calendar)
        let calculator = ScheduleCalculator(calendar: calendar)

        let nudge = try XCTUnwrap(
            calculator.nextNudge(
                after: now,
                interval: 10 * 60,
                startSeconds: 22 * 3_600,
                bedSeconds: 1 * 3_600
            ))

        XCTAssertEqual(nudge.fireDate, now.addingTimeInterval(10 * 60))
        XCTAssertTrue(nudge.window.contains(now))
    }

    func testWallClockScheduleFollowsSelectedTimeZone() throws {
        for identifier in ["Europe/London", "America/Los_Angeles", "Asia/Tokyo"] {
            let calendar = calendar(timeZone: identifier)
            let now = date(2026, 7, 21, 20, calendar: calendar)
            let calculator = ScheduleCalculator(calendar: calendar)

            let nudge = try XCTUnwrap(
                calculator.nextNudge(
                    after: now,
                    interval: 10 * 60,
                    startSeconds: 21 * 3_600 + 30 * 60,
                    bedSeconds: 23 * 3_600
                ))

            XCTAssertEqual(calendar.component(.hour, from: nudge.fireDate), 21, identifier)
            XCTAssertEqual(calendar.component(.minute, from: nudge.fireDate), 40, identifier)
        }
    }

    func testSpringDSTGapResolvesToAValidFutureTime() throws {
        let calendar = calendar()
        let now = date(2026, 3, 29, 0, 30, calendar: calendar)
        let calculator = ScheduleCalculator(calendar: calendar)

        let nudge = try XCTUnwrap(
            calculator.nextNudge(
                after: now,
                interval: 10 * 60,
                startSeconds: 1 * 3_600 + 30 * 60,
                bedSeconds: 3 * 3_600
            ))

        XCTAssertGreaterThan(nudge.fireDate, now)
        XCTAssertTrue((2...3).contains(calendar.component(.hour, from: nudge.fireDate)))
    }

    func testRandomIntervalRangeUsesConfiguredBaseAndSeventyPercentJitter() {
        let range = ScheduleCalculator.intervalRange(frequencyMinutes: 10)

        XCTAssertEqual(range.lowerBound, 600)
        XCTAssertEqual(range.upperBound, 1_020)
    }

    func testNonFiniteIntervalUsesTheSafeDefault() {
        let range = ScheduleCalculator.intervalRange(frequencyMinutes: .nan)

        XCTAssertEqual(range.lowerBound, AppSettings.defaultFrequencyMinutes * 60)
        XCTAssertEqual(range.upperBound, AppSettings.defaultFrequencyMinutes * 60 * 1.7)
    }

    func testSpringDSTGapPreservesMinuteOffsetsAndWindowDuration() throws {
        let calendar = calendar()
        let now = date(2026, 3, 29, 0, 30, calendar: calendar)
        let nudge = try XCTUnwrap(
            ScheduleCalculator(calendar: calendar).nextNudge(
                after: now,
                interval: 5 * 60,
                startSeconds: 1 * 3_600 + 10 * 60,
                bedSeconds: 1 * 3_600 + 50 * 60
            )
        )

        XCTAssertEqual(
            calendar.dateComponents([.hour, .minute], from: nudge.window.start),
            DateComponents(hour: 2, minute: 10)
        )
        XCTAssertEqual(
            calendar.dateComponents([.hour, .minute], from: nudge.window.end),
            DateComponents(hour: 2, minute: 50)
        )
        XCTAssertEqual(nudge.window.duration, 40 * 60)
    }

    func testAutumnDSTRepeatedHourUsesFirstOccurrenceDeterministically() throws {
        let calendar = calendar()
        let now = date(2026, 10, 25, 0, 15, calendar: calendar)
        let nudge = try XCTUnwrap(
            ScheduleCalculator(calendar: calendar).nextNudge(
                after: now,
                interval: 5 * 60,
                startSeconds: 1 * 3_600 + 30 * 60,
                bedSeconds: 2 * 3_600 + 30 * 60
            )
        )

        XCTAssertEqual(
            calendar.dateComponents([.hour, .minute], from: nudge.window.start),
            DateComponents(hour: 1, minute: 30)
        )
        XCTAssertEqual(
            calendar.dateComponents([.hour, .minute], from: nudge.window.end),
            DateComponents(hour: 2, minute: 30)
        )
        XCTAssertEqual(nudge.window.duration, 2 * 3_600)
        XCTAssertEqual(nudge.fireDate, nudge.window.start.addingTimeInterval(5 * 60))
    }

    func testInactiveNightsAreSkipped() throws {
        let calendar = calendar()
        let tuesday = date(2026, 7, 21, 20, calendar: calendar)
        let schedule = WeeklyBedtimeSchedule(
            startSeconds: 21 * 3_600 + 30 * 60,
            bedSeconds: 23 * 3_600,
            activeWeekdays: [5],
            alternateScheduleEnabled: false,
            alternateWeekdays: [],
            alternateStartSeconds: 0,
            alternateBedSeconds: 0
        )

        let nudge = try XCTUnwrap(
            ScheduleCalculator(calendar: calendar).nextNudge(
                after: tuesday,
                interval: 10 * 60,
                schedule: schedule
            )
        )

        XCTAssertEqual(
            calendar.dateComponents([.weekday, .hour, .minute], from: nudge.fireDate),
            DateComponents(hour: 21, minute: 40, weekday: 5)
        )
    }

    func testSelectedSundayUsesAlternateSchedule() throws {
        let calendar = calendar()
        let sunday = date(2026, 7, 26, 22, calendar: calendar)
        let schedule = WeeklyBedtimeSchedule(
            startSeconds: 21 * 3_600,
            bedSeconds: 23 * 3_600,
            activeWeekdays: Set(1...7),
            alternateScheduleEnabled: true,
            alternateWeekdays: [1],
            alternateStartSeconds: 23 * 3_600,
            alternateBedSeconds: 2 * 3_600
        )

        let nudge = try XCTUnwrap(
            ScheduleCalculator(calendar: calendar).nextNudge(
                after: sunday,
                interval: 10 * 60,
                schedule: schedule
            )
        )

        XCTAssertEqual(
            calendar.dateComponents([.day, .hour, .minute], from: nudge.fireDate),
            DateComponents(day: 26, hour: 23, minute: 10)
        )
        XCTAssertEqual(schedule.selection(for: nudge.window.start, calendar: calendar), .alternate)
    }

    func testUnselectedFridayKeepsPrimarySchedule() throws {
        let calendar = calendar()
        let friday = date(2026, 7, 24, 20, calendar: calendar)
        let schedule = WeeklyBedtimeSchedule(
            startSeconds: 21 * 3_600,
            bedSeconds: 23 * 3_600,
            activeWeekdays: Set(1...7),
            alternateScheduleEnabled: true,
            alternateWeekdays: [1],
            alternateStartSeconds: 23 * 3_600,
            alternateBedSeconds: 2 * 3_600
        )

        let nudge = try XCTUnwrap(
            ScheduleCalculator(calendar: calendar).nextNudge(
                after: friday,
                interval: 10 * 60,
                schedule: schedule
            )
        )

        XCTAssertEqual(
            calendar.dateComponents([.day, .hour, .minute], from: nudge.fireDate),
            DateComponents(day: 24, hour: 21, minute: 10)
        )
    }

    func testRotatingCycleAlternatesAfterConfiguredPrimaryRun() {
        let calendar = calendar()
        let anchor = date(2026, 7, 20, 0, calendar: calendar)
        let schedule = WeeklyBedtimeSchedule(
            startSeconds: 21 * 3_600,
            bedSeconds: 23 * 3_600,
            activeWeekdays: Set(1...7),
            alternateScheduleEnabled: true,
            alternateWeekdays: [],
            alternateStartSeconds: 23 * 3_600,
            alternateBedSeconds: 2 * 3_600,
            alternatePattern: .rotatingCycle,
            rotationAnchorDate: anchor,
            rotationPrimaryDays: 4,
            rotationAlternateDays: 4
        )

        XCTAssertFalse(
            schedule.usesAlternateSchedule(
                on: date(2026, 7, 23, 12, calendar: calendar),
                calendar: calendar
            )
        )
        XCTAssertTrue(
            schedule.usesAlternateSchedule(
                on: date(2026, 7, 24, 12, calendar: calendar),
                calendar: calendar
            )
        )
        XCTAssertFalse(
            schedule.usesAlternateSchedule(
                on: date(2026, 7, 28, 12, calendar: calendar),
                calendar: calendar
            )
        )
    }

    func testRotatingCycleRepeatsCorrectlyBeforeAnchor() {
        let calendar = calendar()
        let anchor = date(2026, 7, 20, 0, calendar: calendar)
        let schedule = WeeklyBedtimeSchedule(
            startSeconds: 21 * 3_600,
            bedSeconds: 23 * 3_600,
            activeWeekdays: Set(1...7),
            alternateScheduleEnabled: true,
            alternateWeekdays: [],
            alternateStartSeconds: 23 * 3_600,
            alternateBedSeconds: 2 * 3_600,
            alternatePattern: .rotatingCycle,
            rotationAnchorDate: anchor,
            rotationPrimaryDays: 2,
            rotationAlternateDays: 2
        )

        XCTAssertTrue(
            schedule.usesAlternateSchedule(
                on: date(2026, 7, 19, 12, calendar: calendar),
                calendar: calendar
            )
        )
        XCTAssertFalse(
            schedule.usesAlternateSchedule(
                on: date(2026, 7, 17, 12, calendar: calendar),
                calendar: calendar
            )
        )
    }

    func testOneNightOverrideTakesPriorityOnAnInactiveNight() throws {
        let calendar = calendar()
        let tuesday = date(2026, 7, 21, 20, calendar: calendar)
        let schedule = WeeklyBedtimeSchedule(
            startSeconds: 21 * 3_600,
            bedSeconds: 23 * 3_600,
            activeWeekdays: [],
            alternateScheduleEnabled: false,
            alternateWeekdays: [],
            alternateStartSeconds: 0,
            alternateBedSeconds: 0,
            oneNightOverride: OneNightScheduleOverride(
                anchorDate: tuesday,
                startSeconds: 22 * 3_600,
                bedSeconds: 1 * 3_600
            )
        )

        let nudge = try XCTUnwrap(
            ScheduleCalculator(calendar: calendar).nextNudge(
                after: tuesday,
                interval: 10 * 60,
                schedule: schedule
            )
        )

        XCTAssertEqual(
            calendar.dateComponents([.day, .hour, .minute], from: nudge.fireDate),
            DateComponents(day: 21, hour: 22, minute: 10)
        )
    }

    func testProgressiveModeEscalatesAndResets() {
        var state = ProgressiveState(base: .shy, escalationThreshold: 2)

        state.recordNudge(progressive: true, nextThreshold: 3)
        XCTAssertEqual(state.current, .shy)
        state.recordNudge(progressive: true, nextThreshold: 3)
        XCTAssertEqual(state.current, .insistent)
        state.recordNudge(progressive: true, nextThreshold: 2)
        state.recordNudge(progressive: true, nextThreshold: 2)
        state.recordNudge(progressive: true, nextThreshold: 2)
        XCTAssertEqual(state.current, .zombie)

        state.reset(base: .shy, escalationThreshold: 2)
        XCTAssertEqual(state.current, .shy)
        XCTAssertEqual(state.nudgeCount, 0)
    }

    @MainActor
    func testRememberedSnoozeAndFinishTonightPreserveSchedule() throws {
        let defaults = makeIsolatedDefaults(prefix: "BeddyButler.EverydayTests")
        let settings = AppSettings(defaults: defaults)
        settings.completeOnboarding()
        settings.updateStartSeconds(21 * 3600)
        settings.updateBedSeconds(23 * 3600)
        settings.updateSnoozeMinutes(20)
        let now = date(2026, 7, 21, 22, calendar: .autoupdatingCurrent)
        let scheduler = ButlerTimer(
            settings: settings, audioPlayer: AudioPlayer(), now: { now },
            intervalProvider: { $0.lowerBound }, escalationProvider: { 2 })
        defer { scheduler.timer?.invalidate() }
        scheduler.snooze()
        XCTAssertEqual(settings.mutedUntil, now.addingTimeInterval(20 * 60))
        scheduler.resumeNudges()
        scheduler.finishTonight()
        XCTAssertEqual(settings.mutedUntil, now.addingTimeInterval(60 * 60))
        XCTAssertEqual(settings.startSeconds, 21 * 3600)
        XCTAssertEqual(settings.bedSeconds, 23 * 3600)
        XCTAssertFalse(scheduler.visualNudgePending)
        XCTAssertTrue(scheduler.hasFinishedTonight)
        XCTAssertGreaterThan(try XCTUnwrap(scheduler.nextNudge), try XCTUnwrap(settings.finishedWindowEnd))
        scheduler.undoFinishTonight()
        XCTAssertFalse(scheduler.hasFinishedTonight)
        XCTAssertNil(settings.mutedUntil)
    }

    @MainActor
    func testVisualDeliveryUsesPersistentBadgeWithoutPlayingAudio() throws {
        let defaults = makeIsolatedDefaults(prefix: "BeddyButlerVisualTests")
        let settings = AppSettings(defaults: defaults)
        settings.completeOnboarding()
        settings.updateNudgeDelivery(.visual)
        let audioPlayer = RecordingAudioPlayer()
        settings.updateNotificationAlertsEnabled(true)
        let notifier = RecordingVisualNotifier()
        let scheduler = ButlerTimer(
            settings: settings,
            audioPlayer: audioPlayer,
            visualNotifier: notifier
        )
        defer {
            scheduler.timer?.invalidate()
        }

        scheduler.deliverNudge()

        XCTAssertTrue(scheduler.visualNudgePending)
        XCTAssertEqual(scheduler.pendingVisualNudgeCount, 1)
        XCTAssertEqual(audioPlayer.playCount, 0)
        XCTAssertEqual(notifier.deliveries.count, 1)
        XCTAssertEqual(notifier.deliveries.first?.count, 1)
        XCTAssertNil(notifier.deliveries.first?.personality)
        XCTAssertTrue(scheduler.lastEvent.contains("Visual bedtime badge"))

        scheduler.acknowledgeVisualNudge()
        XCTAssertFalse(scheduler.visualNudgePending)
        XCTAssertEqual(notifier.clearCount, 1)
        XCTAssertEqual(scheduler.lastEvent, "Visual nudge acknowledged.")
    }

    @MainActor
    func testCombinedDeliveryPlaysAudioAndKeepsVisualBadge() throws {
        let defaults = makeIsolatedDefaults(prefix: "BeddyButlerBothTests")
        let settings = AppSettings(defaults: defaults)
        settings.completeOnboarding()
        settings.updateNudgeDelivery(.both)
        let audioPlayer = RecordingAudioPlayer()
        let scheduler = ButlerTimer(settings: settings, audioPlayer: audioPlayer)
        defer {
            scheduler.timer?.invalidate()
        }

        scheduler.deliverNudge()
        scheduler.deliverNudge()

        XCTAssertEqual(audioPlayer.playCount, 2)
        XCTAssertTrue(scheduler.visualNudgePending)
        XCTAssertEqual(scheduler.pendingVisualNudgeCount, 2)
        XCTAssertTrue(scheduler.lastEvent.contains("Shy played"))
        XCTAssertTrue(scheduler.lastEvent.contains("Visual bedtime badge"))
    }

    @MainActor
    func testOverdueTimerDoesNotDeliverOutsideItsScheduledWindow() throws {
        let defaults = makeIsolatedDefaults(prefix: "BeddyButlerOverdueTimerTests")
        let settings = AppSettings(defaults: defaults)
        settings.completeOnboarding()
        settings.updateStartSeconds(21 * 3_600)
        settings.updateBedSeconds(23 * 3_600)
        let currentCalendar = Calendar.autoupdatingCurrent
        var currentDate = date(2026, 7, 21, 22, calendar: currentCalendar)
        let audioPlayer = RecordingAudioPlayer()
        let scheduler = ButlerTimer(
            settings: settings,
            audioPlayer: audioPlayer,
            now: { currentDate },
            intervalProvider: { $0.lowerBound },
            escalationProvider: { 2 }
        )
        defer {
            scheduler.timer?.invalidate()
        }

        currentDate = date(2026, 7, 22, 12, calendar: currentCalendar)
        scheduler.handleTimerFire()

        XCTAssertEqual(audioPlayer.playCount, 0)
        XCTAssertGreaterThan(try XCTUnwrap(scheduler.nextNudge), currentDate)
    }

    @MainActor
    func testLateTimerFireInsideWindowDeliversOneNudgeThenReschedules() throws {
        let defaults = makeIsolatedDefaults(prefix: "BeddyButlerWakeTimerTests")
        let settings = AppSettings(defaults: defaults)
        settings.completeOnboarding()
        settings.updateStartSeconds(21 * 3_600)
        settings.updateBedSeconds(23 * 3_600)
        let currentCalendar = Calendar.autoupdatingCurrent
        var currentDate = date(2026, 7, 21, 22, calendar: currentCalendar)
        let audioPlayer = RecordingAudioPlayer()
        let scheduler = ButlerTimer(
            settings: settings,
            audioPlayer: audioPlayer,
            now: { currentDate },
            intervalProvider: { $0.lowerBound },
            escalationProvider: { 2 }
        )
        defer {
            scheduler.timer?.invalidate()
        }

        currentDate = date(2026, 7, 21, 22, 45, calendar: currentCalendar)
        scheduler.handleTimerFire()

        XCTAssertEqual(audioPlayer.playCount, 1)
        XCTAssertEqual(
            try XCTUnwrap(scheduler.nextNudge),
            currentDate.addingTimeInterval(AppSettings.defaultFrequencyMinutes * 60)
        )
    }

    @MainActor
    func testBackwardClockCorrectionRecalculatesFromCorrectedWallTime() throws {
        let defaults = makeIsolatedDefaults(prefix: "BeddyButlerBackwardClockTests")
        let settings = AppSettings(defaults: defaults)
        settings.completeOnboarding()
        settings.updateStartSeconds(21 * 3_600)
        settings.updateBedSeconds(23 * 3_600)
        settings.updateFrequencyMinutes(10)
        let currentCalendar = Calendar.autoupdatingCurrent
        var currentDate = date(2026, 7, 21, 22, 30, calendar: currentCalendar)
        let scheduler = ButlerTimer(
            settings: settings,
            audioPlayer: AudioPlayer(),
            now: { currentDate },
            intervalProvider: { $0.lowerBound },
            escalationProvider: { 2 }
        )
        defer {
            scheduler.timer?.invalidate()
        }
        let originalNudge = try XCTUnwrap(scheduler.nextNudge)

        currentDate = date(2026, 7, 21, 21, 45, calendar: currentCalendar)
        scheduler.recalculate()

        let correctedNudge = try XCTUnwrap(scheduler.nextNudge)
        XCTAssertEqual(correctedNudge, currentDate.addingTimeInterval(10 * 60))
        XCTAssertLessThan(correctedNudge, originalNudge)
    }

    @MainActor
    func testSnoozeResumesAtPromisedTimeInsideWindow() throws {
        let defaults = makeIsolatedDefaults(prefix: "BeddyButlerSnoozeTests")
        let settings = AppSettings(defaults: defaults)
        settings.completeOnboarding()
        settings.updateStartSeconds(21 * 3_600)
        settings.updateBedSeconds(23 * 3_600)
        settings.updateFrequencyMinutes(10)

        let currentCalendar = Calendar.autoupdatingCurrent
        let now = date(2026, 7, 21, 22, calendar: currentCalendar)
        let scheduler = ButlerTimer(
            settings: settings,
            audioPlayer: AudioPlayer(),
            now: { now },
            intervalProvider: { $0.lowerBound },
            escalationProvider: { 2 }
        )
        defer {
            scheduler.timer?.invalidate()
        }

        XCTAssertTrue(scheduler.canSnooze)
        scheduler.snooze(minutes: 30)

        XCTAssertEqual(settings.mutedUntil, now.addingTimeInterval(30 * 60))
        XCTAssertEqual(scheduler.nextNudge, now.addingTimeInterval(30 * 60))
        XCTAssertEqual(scheduler.timer?.tolerance, 30)
        XCTAssertTrue(scheduler.lastEvent.hasPrefix("Snoozed until "))
    }

    @MainActor
    func testSnoozeOutsideWindowDoesNotChangeMuteState() throws {
        let defaults = makeIsolatedDefaults(prefix: "BeddyButlerSnoozeTests")
        let settings = AppSettings(defaults: defaults)
        settings.completeOnboarding()
        settings.updateStartSeconds(21 * 3_600)
        settings.updateBedSeconds(23 * 3_600)

        let currentCalendar = Calendar.autoupdatingCurrent
        let now = date(2026, 7, 21, 12, calendar: currentCalendar)
        let scheduler = ButlerTimer(
            settings: settings,
            audioPlayer: AudioPlayer(),
            now: { now },
            intervalProvider: { $0.lowerBound },
            escalationProvider: { 2 }
        )
        defer {
            scheduler.timer?.invalidate()
        }

        XCTAssertFalse(scheduler.canSnooze)
        scheduler.snooze()

        XCTAssertNil(settings.mutedUntil)
        XCTAssertEqual(scheduler.lastEvent, "Snooze is available during your bedtime window.")
    }

    @MainActor
    func testSnoozeThatReachesBedtimePausesUntilTomorrow() throws {
        let defaults = makeIsolatedDefaults(prefix: "BeddyButlerSnoozeTests")
        let settings = AppSettings(defaults: defaults)
        settings.completeOnboarding()
        settings.updateStartSeconds(21 * 3_600)
        settings.updateBedSeconds(23 * 3_600)
        settings.updateFrequencyMinutes(10)

        let currentCalendar = Calendar.autoupdatingCurrent
        let now = date(2026, 7, 21, 22, 50, calendar: currentCalendar)
        let scheduler = ButlerTimer(
            settings: settings,
            audioPlayer: AudioPlayer(),
            now: { now },
            intervalProvider: { $0.lowerBound },
            escalationProvider: { 2 }
        )
        defer {
            scheduler.timer?.invalidate()
        }

        scheduler.snooze(minutes: 30)

        let mutedUntil = try XCTUnwrap(settings.mutedUntil)
        XCTAssertEqual(
            currentCalendar.dateComponents([.day, .hour, .minute], from: mutedUntil),
            DateComponents(day: 21, hour: 23, minute: 0)
        )
        let nextNudge = try XCTUnwrap(scheduler.nextNudge)
        XCTAssertEqual(
            currentCalendar.dateComponents([.day, .hour, .minute], from: nextNudge),
            DateComponents(day: 22, hour: 21, minute: 10)
        )
        XCTAssertEqual(scheduler.lastEvent, "Snooze reaches bedtime, so nudges are paused for tonight.")
    }

    @MainActor
    func testFrequencyAndDeliveryEditsPreservePromisedSnoozeResume() throws {
        let defaults = makeIsolatedDefaults(prefix: "BeddyButlerSnoozeEditTests")
        let settings = AppSettings(defaults: defaults)
        settings.completeOnboarding()
        settings.updateStartSeconds(21 * 3_600)
        settings.updateBedSeconds(23 * 3_600)
        let currentCalendar = Calendar.autoupdatingCurrent
        let now = date(2026, 7, 21, 22, calendar: currentCalendar)
        let scheduler = ButlerTimer(
            settings: settings,
            audioPlayer: AudioPlayer(),
            now: { now },
            intervalProvider: { $0.lowerBound },
            escalationProvider: { 2 }
        )
        defer {
            scheduler.timer?.invalidate()
        }

        scheduler.snooze(minutes: 30)
        settings.updateFrequencyMinutes(20)
        settings.updateNudgeDelivery(.visual)

        XCTAssertEqual(settings.mutedUntil, now.addingTimeInterval(30 * 60))
        XCTAssertEqual(scheduler.nextNudge, now.addingTimeInterval(30 * 60))
        XCTAssertEqual(scheduler.nextPersonality, settings.personality)
    }

    @MainActor
    func testDisablingCurrentNightWhileSnoozedMovesToNextActiveWindow() throws {
        let defaults = makeIsolatedDefaults(prefix: "BeddyButlerSnoozeNightEditTests")
        let settings = AppSettings(defaults: defaults)
        settings.completeOnboarding()
        settings.updateStartSeconds(21 * 3_600)
        settings.updateBedSeconds(23 * 3_600)
        settings.updateFrequencyMinutes(10)
        let currentCalendar = Calendar.autoupdatingCurrent
        let now = date(2026, 7, 21, 22, calendar: currentCalendar)
        let scheduler = ButlerTimer(
            settings: settings,
            audioPlayer: AudioPlayer(),
            now: { now },
            intervalProvider: { $0.lowerBound },
            escalationProvider: { 2 }
        )
        defer {
            scheduler.timer?.invalidate()
        }

        scheduler.snooze(minutes: 30)
        settings.updateActiveWeekday(
            currentCalendar.component(.weekday, from: now),
            isActive: false
        )

        let nextNudge = try XCTUnwrap(scheduler.nextNudge)
        XCTAssertEqual(
            currentCalendar.dateComponents([.day, .hour, .minute], from: nextNudge),
            DateComponents(day: 22, hour: 21, minute: 10)
        )
        XCTAssertGreaterThan(nextNudge, try XCTUnwrap(settings.mutedUntil))
    }

    // MARK: - Scheduler integration

    @MainActor
    private func activatedSettings(
        _ label: String
    ) throws -> (settings: AppSettings, defaults: UserDefaults) {
        let defaults = makeIsolatedDefaults(prefix: "BeddyButler.\(label)")
        let settings = AppSettings(defaults: defaults)
        settings.completeOnboarding()
        settings.updateStartSeconds(21 * 3_600)
        settings.updateBedSeconds(23 * 3_600)
        return (settings, defaults)
    }

    @MainActor
    private func makeScheduler(
        _ settings: AppSettings,
        clock: TestClock,
        audio: RecordingAudioPlayer = RecordingAudioPlayer(),
        notifier: RecordingVisualNotifier? = nil,
        intervalProvider: @escaping (ClosedRange<TimeInterval>) -> TimeInterval = { $0.lowerBound }
    ) -> ButlerTimer {
        ButlerTimer(
            settings: settings,
            audioPlayer: audio,
            now: { clock.now },
            intervalProvider: intervalProvider,
            escalationProvider: { 2 },
            visualNotifier: notifier
        )
    }

    @MainActor
    func testCrossingWindowBoundariesPublishWithoutRedrawingTheNudge() throws {
        let (settings, _) = try activatedSettings("Boundary")
        let calendar = Calendar.autoupdatingCurrent
        let clock = TestClock(date(2026, 7, 21, 20, calendar: calendar))
        var draws = 0
        let scheduler = makeScheduler(settings, clock: clock) { range in
            draws += 1
            return range.lowerBound
        }
        defer { scheduler.invalidateTimers() }
        var publishes = 0
        var posts = 0
        let publishSubscription = scheduler.objectWillChange.sink { publishes += 1 }
        let postSubscription = NotificationCenter.default
            .publisher(for: .beddyScheduleDidChange, object: scheduler)
            .sink { _ in posts += 1 }
        defer {
            publishSubscription.cancel()
            postSubscription.cancel()
        }
        let drawsAfterInit = draws
        let nudge = try XCTUnwrap(scheduler.nextNudge)

        XCTAssertEqual(scheduler.boundaryTimer?.fireDate, date(2026, 7, 21, 21, calendar: calendar))
        clock.now = date(2026, 7, 21, 21, calendar: calendar)
        scheduler.refreshTimeDependentState()
        XCTAssertTrue(scheduler.canSnooze)
        XCTAssertGreaterThan(publishes, 0)
        XCTAssertEqual(posts, 1)
        XCTAssertEqual(scheduler.boundaryTimer?.fireDate, date(2026, 7, 21, 23, calendar: calendar))

        clock.now = date(2026, 7, 21, 23, calendar: calendar)
        scheduler.refreshTimeDependentState()
        XCTAssertFalse(scheduler.canSnooze)
        XCTAssertEqual(posts, 2)
        XCTAssertEqual(scheduler.boundaryTimer?.fireDate, date(2026, 7, 22, 21, calendar: calendar))
        XCTAssertEqual(draws, drawsAfterInit)
        XCTAssertEqual(scheduler.nextNudge, nudge)
    }

    @MainActor
    func testBoundaryRefreshClearsAnEndedPause() throws {
        let (settings, _) = try activatedSettings("PauseBoundary")
        let calendar = Calendar.autoupdatingCurrent
        let clock = TestClock(date(2026, 7, 21, 22, calendar: calendar))
        let scheduler = makeScheduler(settings, clock: clock)
        defer { scheduler.invalidateTimers() }

        scheduler.snooze(minutes: 20)
        let mutedUntil = try XCTUnwrap(settings.mutedUntil)
        XCTAssertEqual(scheduler.boundaryTimer?.fireDate, mutedUntil)

        clock.now = mutedUntil
        scheduler.refreshTimeDependentState()
        XCTAssertNil(settings.mutedUntil)
        XCTAssertTrue(scheduler.canSnooze)
    }

    @MainActor
    func testStaleFinishTonightAfterBedtimePublishesAndDoesNotFinish() throws {
        let (settings, _) = try activatedSettings("StaleFinish")
        let calendar = Calendar.autoupdatingCurrent
        let clock = TestClock(date(2026, 7, 21, 22, calendar: calendar))
        let scheduler = makeScheduler(settings, clock: clock)
        defer { scheduler.invalidateTimers() }
        var publishes = 0
        let subscription = scheduler.objectWillChange.sink { publishes += 1 }
        defer { subscription.cancel() }

        clock.now = date(2026, 7, 21, 23, 5, calendar: calendar)
        scheduler.finishTonight()

        XCTAssertGreaterThan(publishes, 0)
        XCTAssertNil(settings.finishedWindowEnd)
        XCTAssertNil(settings.mutedUntil)
        XCTAssertFalse(scheduler.hasFinishedTonight)
    }

    @MainActor
    func testUnrelatedChangesAndActivationKeepThePendingNudge() throws {
        let (settings, _) = try activatedSettings("Preserve")
        settings.updateFrequencyMinutes(10)
        let calendar = Calendar.autoupdatingCurrent
        let clock = TestClock(date(2026, 7, 21, 22, calendar: calendar))
        var draws = 0
        let scheduler = makeScheduler(settings, clock: clock) { range in
            draws += 1
            return range.lowerBound + Double(draws) * 17
        }
        defer { scheduler.invalidateTimers() }
        let original = try XCTUnwrap(scheduler.nextNudge)
        let drawsAfterInit = draws

        settings.updateVoiceVolume(0.35)
        settings.updatePrimaryScheduleName("Weeknights")
        clock.now = clock.now.addingTimeInterval(120)
        scheduler.recalculate(preservingPendingNudge: true)
        settings.updatePersonality(.insistent)

        XCTAssertEqual(scheduler.nextNudge, original)
        XCTAssertEqual(draws, drawsAfterInit)
        XCTAssertEqual(scheduler.nextPersonality, .insistent)
        XCTAssertEqual(scheduler.timer?.fireDate, original)
    }

    @MainActor
    func testScheduleAffectingChangesRedrawThePendingNudge() throws {
        let (settings, _) = try activatedSettings("Redraw")
        settings.updateFrequencyMinutes(10)
        let calendar = Calendar.autoupdatingCurrent
        let clock = TestClock(date(2026, 7, 21, 22, calendar: calendar))
        var draws = 0
        let scheduler = makeScheduler(settings, clock: clock) { range in
            draws += 1
            return range.lowerBound + Double(draws) * 17
        }
        defer { scheduler.invalidateTimers() }
        let original = try XCTUnwrap(scheduler.nextNudge)

        settings.updateFrequencyMinutes(2)
        let shorter = try XCTUnwrap(scheduler.nextNudge)
        XCTAssertLessThan(shorter, original)

        let drawsBeforeEdit = draws
        settings.updateStartSeconds(20 * 3_600)
        XCTAssertEqual(draws, drawsBeforeEdit + 1)
        XCTAssertNotEqual(scheduler.nextNudge, shorter)

        let drawsBeforeSleep = draws
        scheduler.invalidateTimers()
        scheduler.recalculate(preservingPendingNudge: true)
        XCTAssertEqual(draws, drawsBeforeSleep + 1)
        XCTAssertEqual(scheduler.timer?.isValid, true)
    }

    @MainActor
    func testResumeMidSnoozeRedrawsInsteadOfKeepingTheSnoozeEnd() throws {
        let (settings, _) = try activatedSettings("ResumeRedraw")
        let calendar = Calendar.autoupdatingCurrent
        let clock = TestClock(date(2026, 7, 21, 22, 50, calendar: calendar))
        let scheduler = makeScheduler(settings, clock: clock)
        defer { scheduler.invalidateTimers() }

        scheduler.snooze(minutes: 5)
        XCTAssertEqual(scheduler.nextNudge, clock.now.addingTimeInterval(5 * 60))
        scheduler.resumeNudges()

        // Without the snapshot check, the 22:55 snooze end would be kept as the next nudge.
        XCTAssertNil(settings.mutedUntil)
        XCTAssertEqual(scheduler.nextNudge, clock.now.addingTimeInterval(AppSettings.defaultFrequencyMinutes * 60))
    }

    @MainActor
    func testExpiredOneNightAdjustmentIsClearedWithoutANestedReschedule() throws {
        let (settings, _) = try activatedSettings("ExpiredOverride")
        let calendar = Calendar.autoupdatingCurrent
        settings.enableTonightOverride(on: date(2026, 7, 20, 20, calendar: calendar), calendar: calendar)
        XCTAssertNotNil(settings.tonightOverrideDate)
        let clock = TestClock(date(2026, 7, 21, 22, calendar: calendar))
        var draws = 0
        var posts = 0
        let subscription = NotificationCenter.default
            .publisher(for: .beddySettingsDidChange, object: settings)
            .sink { _ in posts += 1 }
        defer { subscription.cancel() }

        let scheduler = makeScheduler(settings, clock: clock) { range in
            draws += 1
            return range.lowerBound
        }
        defer { scheduler.invalidateTimers() }

        XCTAssertNil(settings.tonightOverrideDate)
        XCTAssertEqual(draws, 1)
        XCTAssertEqual(posts, 0)
        XCTAssertEqual(scheduler.timer?.fireDate, scheduler.nextNudge)
    }

    func testEqualBeginAndBedTimesHaveNoWindow() {
        let calendar = calendar()
        let now = date(2026, 7, 21, 20, calendar: calendar)
        XCTAssertNil(
            ScheduleCalculator(calendar: calendar).nextNudge(
                after: now,
                interval: 10 * 60,
                startSeconds: 22 * 3_600,
                bedSeconds: 22 * 3_600
            )
        )
    }

    @MainActor
    func testEqualBeginAndBedTimesScheduleNothing() throws {
        let (settings, _) = try activatedSettings("EqualTimes")
        settings.updateBedSeconds(21 * 3_600)
        let clock = TestClock(date(2026, 7, 21, 22, calendar: .autoupdatingCurrent))
        let scheduler = makeScheduler(settings, clock: clock)
        defer { scheduler.invalidateTimers() }

        XCTAssertNil(scheduler.nextNudge)
        XCTAssertNil(scheduler.timer)
        XCTAssertFalse(scheduler.canSnooze)
        XCTAssertEqual(scheduler.lastEvent, "No valid bedtime window is configured.")
    }

    func testWindowBeginningInsideSpringForwardGapStartsAtFirstValidInstant() throws {
        let london = calendar()
        let londonWindow = try XCTUnwrap(
            ScheduleCalculator(calendar: london).window(
                containingOrAfter: date(2026, 3, 29, 0, calendar: london),
                startSeconds: 1 * 3_600 + 30 * 60,
                bedSeconds: 2 * 3_600 + 15 * 60
            )
        )
        XCTAssertEqual(
            london.dateComponents([.day, .hour, .minute], from: londonWindow.start),
            DateComponents(day: 29, hour: 2, minute: 0)
        )
        XCTAssertEqual(
            london.dateComponents([.day, .hour, .minute], from: londonWindow.end),
            DateComponents(day: 29, hour: 2, minute: 15)
        )

        let santiago = calendar(timeZone: "America/Santiago")
        let beforeGap = date(2026, 9, 5, 23, calendar: santiago)
        let santiagoWindow = try XCTUnwrap(
            ScheduleCalculator(calendar: santiago).window(
                containingOrAfter: beforeGap,
                startSeconds: 30 * 60,
                bedSeconds: 1 * 3_600 + 30 * 60
            )
        )
        XCTAssertEqual(
            santiago.dateComponents([.day, .hour, .minute], from: santiagoWindow.start),
            DateComponents(day: 6, hour: 1, minute: 0)
        )
        XCTAssertEqual(santiagoWindow.duration, 30 * 60)

        // A window lying wholly inside the gap has no duration, so that night is skipped.
        let emptyWindow = try XCTUnwrap(
            ScheduleCalculator(calendar: santiago).window(
                containingOrAfter: beforeGap,
                startSeconds: 30 * 60,
                bedSeconds: 1 * 3_600
            )
        )
        XCTAssertEqual(santiago.component(.day, from: emptyWindow.start), 7)
    }

    @MainActor
    func testProgressiveCeilingBelowSelectedPersonalityDoesNotSoftenNudges() throws {
        let (settings, _) = try activatedSettings("Ceiling")
        settings.updatePersonality(.zombie)
        settings.updateMaximumPersonality(.shy)
        settings.updateProgressiveMode(true)
        let audio = RecordingAudioPlayer()
        let clock = TestClock(date(2026, 7, 21, 21, 5, calendar: .autoupdatingCurrent))
        let scheduler = makeScheduler(settings, clock: clock, audio: audio)
        defer { scheduler.invalidateTimers() }

        XCTAssertEqual(settings.effectiveMaximumPersonality, .zombie)
        XCTAssertEqual(scheduler.nextPersonality, .zombie)
        clock.now = try XCTUnwrap(scheduler.nextNudge)
        scheduler.handleTimerFire()
        XCTAssertEqual(audio.personalities, [.zombie])
    }

    @MainActor
    func testProgressiveEscalationStopsAtTheCeiling() throws {
        let (settings, _) = try activatedSettings("Escalation")
        settings.updateProgressiveMode(true)
        settings.updateMaximumPersonality(.insistent)
        let audio = RecordingAudioPlayer()
        let clock = TestClock(date(2026, 7, 21, 21, 5, calendar: .autoupdatingCurrent))
        let scheduler = makeScheduler(settings, clock: clock, audio: audio)
        defer { scheduler.invalidateTimers() }

        for _ in 0..<7 {
            clock.now = try XCTUnwrap(scheduler.nextNudge)
            scheduler.handleTimerFire()
        }

        XCTAssertEqual(audio.playCount, 7)
        XCTAssertEqual(Array(audio.personalities.prefix(2)), [.shy, .shy])
        XCTAssertTrue(audio.personalities.contains(.insistent))
        XCTAssertFalse(audio.personalities.contains(.zombie))
    }

    @MainActor
    func testProgressiveModeDoesNotEscalateVisualOnlyNudges() throws {
        let (settings, _) = try activatedSettings("VisualProgressive")
        settings.updateProgressiveMode(true)
        settings.updateNudgeDelivery(.visual)
        let clock = TestClock(date(2026, 7, 21, 21, 5, calendar: .autoupdatingCurrent))
        let scheduler = makeScheduler(settings, clock: clock)
        defer { scheduler.invalidateTimers() }

        for _ in 0..<4 {
            clock.now = try XCTUnwrap(scheduler.nextNudge)
            scheduler.handleTimerFire()
        }

        XCTAssertEqual(settings.pendingVisualNudgeCount, 4)
        XCTAssertEqual(scheduler.nextPersonality, .shy)
    }

    @MainActor
    func testPauseTonightInsideAndBeforeWindowEndsAtBedtime() throws {
        let calendar = Calendar.autoupdatingCurrent
        for hour in [22, 12] {
            let (settings, _) = try activatedSettings("PauseTonight")
            let notifier = RecordingVisualNotifier()
            let clock = TestClock(date(2026, 7, 21, hour, calendar: calendar))
            let scheduler = makeScheduler(settings, clock: clock, notifier: notifier)
            defer { scheduler.invalidateTimers() }

            scheduler.muteForCurrentWindow()

            XCTAssertEqual(settings.mutedUntil, date(2026, 7, 21, 23, calendar: calendar), "\(hour)")
            XCTAssertEqual(notifier.clearCount, 1, "\(hour)")
            XCTAssertFalse(scheduler.isSnoozed, "\(hour)")
            XCTAssertEqual(
                calendar.dateComponents([.day, .hour], from: try XCTUnwrap(scheduler.nextNudge)),
                DateComponents(day: 22, hour: 21),
                "\(hour)"
            )
        }
    }

    @MainActor
    func testSnoozeEndDeliversOneNudge() throws {
        let (settings, _) = try activatedSettings("SnoozeEnd")
        let audio = RecordingAudioPlayer()
        let clock = TestClock(date(2026, 7, 21, 22, calendar: .autoupdatingCurrent))
        let scheduler = makeScheduler(settings, clock: clock, audio: audio)
        defer { scheduler.invalidateTimers() }

        scheduler.snooze(minutes: 20)
        clock.now = try XCTUnwrap(settings.mutedUntil)
        scheduler.handleTimerFire()

        XCTAssertEqual(audio.playCount, 1)
        XCTAssertNil(settings.mutedUntil)
        XCTAssertGreaterThan(try XCTUnwrap(scheduler.nextNudge), clock.now)
    }

    @MainActor
    func testWhileSnoozedTheUserCanFinishOrPauseTonight() throws {
        let calendar = Calendar.autoupdatingCurrent
        let (settings, _) = try activatedSettings("SnoozedActions")
        let clock = TestClock(date(2026, 7, 21, 22, calendar: calendar))
        let scheduler = makeScheduler(settings, clock: clock)
        defer { scheduler.invalidateTimers() }

        scheduler.snooze(minutes: 20)
        XCTAssertTrue(scheduler.isSnoozed)
        XCTAssertFalse(scheduler.canSnooze)
        scheduler.finishTonight()
        XCTAssertTrue(scheduler.hasFinishedTonight)
        XCTAssertEqual(settings.mutedUntil, date(2026, 7, 21, 23, calendar: calendar))
        XCTAssertFalse(scheduler.isSnoozed)

        scheduler.undoFinishTonight()
        scheduler.snooze(minutes: 20)
        scheduler.muteForCurrentWindow()
        XCTAssertEqual(settings.mutedUntil, date(2026, 7, 21, 23, calendar: calendar))
        XCTAssertFalse(scheduler.isSnoozed)
    }

    @MainActor
    func testSnoozeClampedToBedtimeCountsAsPausedNotSnoozed() throws {
        let (settings, _) = try activatedSettings("ClampedSnooze")
        let clock = TestClock(date(2026, 7, 21, 22, 50, calendar: .autoupdatingCurrent))
        let scheduler = makeScheduler(settings, clock: clock)
        defer { scheduler.invalidateTimers() }

        scheduler.snooze(minutes: 30)

        XCTAssertTrue(settings.isMuted(at: clock.now))
        XCTAssertFalse(scheduler.isSnoozed)
    }

    @MainActor
    func testStaleSnoozeDoesNotShortenAPause() throws {
        let calendar = Calendar.autoupdatingCurrent
        let (settings, _) = try activatedSettings("StaleSnooze")
        let clock = TestClock(date(2026, 7, 21, 22, calendar: calendar))
        let scheduler = makeScheduler(settings, clock: clock)
        defer { scheduler.invalidateTimers() }

        scheduler.muteForCurrentWindow()
        scheduler.snooze(minutes: 10)

        XCTAssertEqual(settings.mutedUntil, date(2026, 7, 21, 23, calendar: calendar))
        XCTAssertEqual(scheduler.lastEvent, "Nudges are paused for this bedtime window.")
    }

    @MainActor
    func testFinishAndPauseFollowALaterBedtime() throws {
        let calendar = Calendar.autoupdatingCurrent
        for finishes in [true, false] {
            let (settings, defaults) = try activatedSettings("WidenedWindow")
            let clock = TestClock(date(2026, 7, 21, 22, calendar: calendar))
            let scheduler = makeScheduler(settings, clock: clock)
            defer { scheduler.invalidateTimers() }

            if finishes {
                scheduler.finishTonight()
            } else {
                scheduler.muteForCurrentWindow()
            }
            settings.updateBedSeconds(0)

            let midnight = date(2026, 7, 22, 0, calendar: calendar)
            XCTAssertEqual(settings.mutedUntil, midnight, "finish: \(finishes)")
            XCTAssertEqual(scheduler.hasFinishedTonight, finishes)
            XCTAssertEqual(
                calendar.dateComponents([.day, .hour], from: try XCTUnwrap(scheduler.nextNudge)),
                DateComponents(day: 22, hour: 21),
                "finish: \(finishes)"
            )
            XCTAssertEqual(AppSettings(defaults: defaults).mutedUntil, midnight)
        }
    }

    @MainActor
    func testShortSnoozeDoesNotFollowALaterBedtime() throws {
        let (settings, _) = try activatedSettings("SnoozeWidened")
        let clock = TestClock(date(2026, 7, 21, 22, calendar: .autoupdatingCurrent))
        let scheduler = makeScheduler(settings, clock: clock)
        defer { scheduler.invalidateTimers() }

        scheduler.snooze(minutes: 20)
        settings.updateBedSeconds(0)

        XCTAssertEqual(settings.mutedUntil, clock.now.addingTimeInterval(20 * 60))
        XCTAssertEqual(scheduler.nextNudge, clock.now.addingTimeInterval(20 * 60))
    }

    @MainActor
    func testResumeAfterFinishingRestoresSetAsideBadges() throws {
        let (settings, _) = try activatedSettings("ResumeFinished")
        settings.updateNudgeDelivery(.visual)
        let clock = TestClock(date(2026, 7, 21, 22, calendar: .autoupdatingCurrent))
        let scheduler = makeScheduler(settings, clock: clock)
        defer { scheduler.invalidateTimers() }
        scheduler.deliverNudge()
        scheduler.deliverNudge()

        scheduler.finishTonight()
        XCTAssertEqual(scheduler.pendingVisualNudgeCount, 0)
        scheduler.resumeNudges()

        XCTAssertEqual(scheduler.pendingVisualNudgeCount, 2)
        XCTAssertFalse(scheduler.hasFinishedTonight)
        XCTAssertNil(settings.mutedUntil)
    }

    @MainActor
    func testVisualPreviewShowsOneBadgeAndNoneAfterFinishing() throws {
        let (settings, _) = try activatedSettings("Preview")
        settings.updateNudgeDelivery(.visual)
        let clock = TestClock(date(2026, 7, 21, 22, calendar: .autoupdatingCurrent))
        let scheduler = makeScheduler(settings, clock: clock)
        defer { scheduler.invalidateTimers() }

        scheduler.previewSelectedNudge()
        scheduler.previewSelectedNudge()
        XCTAssertEqual(scheduler.pendingVisualNudgeCount, 1)

        scheduler.acknowledgeVisualNudge()
        scheduler.finishTonight()
        scheduler.previewSelectedNudge()
        XCTAssertEqual(scheduler.pendingVisualNudgeCount, 0)
        XCTAssertEqual(scheduler.lastEvent, "Good night.")
    }

    @MainActor
    func testStatusMessagesNeverExposeClipFileNames() throws {
        let (settings, _) = try activatedSettings("ClipNames")
        settings.updateNudgeDelivery(.both)
        let clock = TestClock(date(2026, 7, 21, 22, calendar: .autoupdatingCurrent))
        let scheduler = makeScheduler(settings, clock: clock)
        defer { scheduler.invalidateTimers() }

        scheduler.previewNudge(.insistent)
        XCTAssertTrue(scheduler.lastEvent.hasPrefix("Previewed an Insistent reminder."))
        assertNoClipFileName(in: scheduler.lastEvent)

        scheduler.deliverNudge()
        XCTAssertTrue(scheduler.lastEvent.hasPrefix("Shy played at "))
        assertNoClipFileName(in: scheduler.lastEvent)
    }

    private func assertNoClipFileName(in message: String, line: UInt = #line) {
        for fragment in [".mp3", "20151210", "Nell Watson", "18tuned"] {
            XCTAssertFalse(message.contains(fragment), "\(message) leaks \(fragment)", line: line)
        }
    }

    func testPlaybackErrorsDoNotNameTheClipFile() {
        let clip = URL(fileURLWithPath: "/tmp/20151210 - Nell Watson - Shy.18tuned.mp3")
        let errors: [AudioPlayerError] = [
            .playbackRefused(clip),
            .playbackFailed(clip, CocoaError(.fileReadCorruptFile)),
        ]
        for error in errors {
            let description = error.localizedDescription
            XCTAssertFalse(description.contains("20151210"), description)
            XCTAssertFalse(description.contains(".mp3"), description)
        }
    }

    @MainActor
    func testQuietingActionsStopAClipThatIsStillPlaying() throws {
        let (settings, _) = try activatedSettings("StopAudio")
        settings.updateNudgeDelivery(.both)
        let audio = RecordingAudioPlayer()
        let clock = TestClock(date(2026, 7, 21, 21, 30, calendar: .autoupdatingCurrent))
        let scheduler = makeScheduler(settings, clock: clock, audio: audio)
        defer { scheduler.invalidateTimers() }

        scheduler.deliverNudge()
        scheduler.acknowledgeVisualNudge()
        XCTAssertEqual(audio.stopCount, 1)

        scheduler.snooze(minutes: 10)
        XCTAssertEqual(audio.stopCount, 2)
        scheduler.resumeNudges()
        XCTAssertEqual(audio.stopCount, 2, "Resuming must not stop audio")

        scheduler.snooze(minutes: 120)  // Reaches bedtime, so it pauses the window.
        XCTAssertEqual(audio.stopCount, 3)
        scheduler.resumeNudges()

        scheduler.muteForCurrentWindow()
        XCTAssertEqual(audio.stopCount, 4)
        scheduler.resumeNudges()

        scheduler.finishTonight()
        XCTAssertEqual(audio.stopCount, 5)
        scheduler.undoFinishTonight()
        scheduler.previewSelectedNudge()
        XCTAssertEqual(audio.stopCount, 5, "Undo and preview must not stop audio")
    }

    @MainActor
    func testWakeInsideWindowRecalculatesWithoutCatchingUp() throws {
        let (settings, _) = try activatedSettings("Wake")
        let audio = RecordingAudioPlayer()
        let clock = TestClock(date(2026, 7, 21, 20, calendar: .autoupdatingCurrent))
        let scheduler = makeScheduler(settings, clock: clock, audio: audio)
        defer { scheduler.invalidateTimers() }

        scheduler.invalidateTimers()  // The Mac sleeps through the first nudge.
        clock.now = date(2026, 7, 21, 22, 45, calendar: .autoupdatingCurrent)
        scheduler.recalculate()  // What systemDidWake does.

        XCTAssertEqual(audio.playCount, 0)
        XCTAssertGreaterThan(try XCTUnwrap(scheduler.nextNudge), clock.now)
        XCTAssertEqual(scheduler.timer?.isValid, true)
    }
}
