import Foundation
import XCTest

@testable import Beddy_Butler

@MainActor
private final class RecordingAudioPlayer: AudioPlaying {
    private(set) var playCount = 0

    func play(_ personality: ButlerPersonality, volume: Double) throws -> URL {
        playCount += 1
        return URL(fileURLWithPath: "/tmp/\(personality.rawValue).mp3")
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

final class BeddyButlerTimerTests: XCTestCase {
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
    func testVisualDeliveryUsesPersistentBadgeWithoutPlayingAudio() throws {
        let suiteName = "BeddyButlerVisualTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let settings = AppSettings(defaults: defaults)
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
            defaults.removePersistentDomain(forName: suiteName)
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
        let suiteName = "BeddyButlerBothTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let settings = AppSettings(defaults: defaults)
        settings.updateNudgeDelivery(.both)
        let audioPlayer = RecordingAudioPlayer()
        let scheduler = ButlerTimer(settings: settings, audioPlayer: audioPlayer)
        defer {
            scheduler.timer?.invalidate()
            defaults.removePersistentDomain(forName: suiteName)
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
        let suiteName = "BeddyButlerOverdueTimerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(defaults: defaults)
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
            defaults.removePersistentDomain(forName: suiteName)
        }

        currentDate = date(2026, 7, 22, 12, calendar: currentCalendar)
        scheduler.handleTimerFire()

        XCTAssertEqual(audioPlayer.playCount, 0)
        XCTAssertGreaterThan(try XCTUnwrap(scheduler.nextNudge), currentDate)
    }

    @MainActor
    func testWakeInsideWindowDeliversOneOverdueNudgeThenReschedules() throws {
        let suiteName = "BeddyButlerWakeTimerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(defaults: defaults)
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
            defaults.removePersistentDomain(forName: suiteName)
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
        let suiteName = "BeddyButlerBackwardClockTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(defaults: defaults)
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
            defaults.removePersistentDomain(forName: suiteName)
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
        let suiteName = "BeddyButlerSnoozeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(defaults: defaults)
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
            defaults.removePersistentDomain(forName: suiteName)
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
        let suiteName = "BeddyButlerSnoozeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(defaults: defaults)
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
            defaults.removePersistentDomain(forName: suiteName)
        }

        XCTAssertFalse(scheduler.canSnooze)
        scheduler.snooze()

        XCTAssertNil(settings.mutedUntil)
        XCTAssertEqual(scheduler.lastEvent, "Snooze is available during your bedtime window.")
    }

    @MainActor
    func testSnoozeThatReachesBedtimePausesUntilTomorrow() throws {
        let suiteName = "BeddyButlerSnoozeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(defaults: defaults)
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
            defaults.removePersistentDomain(forName: suiteName)
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
        let suiteName = "BeddyButlerSnoozeEditTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(defaults: defaults)
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
            defaults.removePersistentDomain(forName: suiteName)
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
        let suiteName = "BeddyButlerSnoozeNightEditTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(defaults: defaults)
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
            defaults.removePersistentDomain(forName: suiteName)
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
}
