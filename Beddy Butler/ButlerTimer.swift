import Cocoa
import Foundation
import OSLog

struct BedtimeWindow: Equatable, Sendable {
    let start: Date
    let end: Date

    var duration: TimeInterval { end.timeIntervalSince(start) }

    func contains(_ date: Date) -> Bool {
        start <= date && date < end
    }
}

struct ScheduledNudge: Equatable, Sendable {
    let fireDate: Date
    let window: BedtimeWindow
}

enum WallClockDateResolver {
    static func date(
        seconds: Int,
        on day: Date,
        calendar: Calendar,
        matchingPolicy: Calendar.MatchingPolicy = .nextTimePreservingSmallerComponents
    ) -> Date? {
        let clamped = min(max(seconds, 0), AppSettings.secondsPerDay - 1)
        let components = DateComponents(
            hour: clamped / 3_600,
            minute: (clamped % 3_600) / 60,
            second: clamped % 60
        )
        let searchStart = calendar.startOfDay(for: day).addingTimeInterval(-1)
        return calendar.nextDate(
            after: searchStart,
            matching: components,
            matchingPolicy: matchingPolicy,
            repeatedTimePolicy: .first,
            direction: .forward
        )
    }
}

struct OneNightScheduleOverride: Equatable, Sendable {
    let anchorDate: Date
    let startSeconds: Int
    let bedSeconds: Int
}

enum BedtimeScheduleSelection: Equatable, Sendable {
    case primary
    case alternate
    case oneNightOverride
}

struct WeeklyBedtimeSchedule: Equatable, Sendable {
    let startSeconds: Int
    let bedSeconds: Int
    let activeWeekdays: Set<Int>
    let alternateScheduleEnabled: Bool
    let alternateWeekdays: Set<Int>
    let alternateStartSeconds: Int
    let alternateBedSeconds: Int
    let alternatePattern: AlternateSchedulePattern
    let rotationAnchorDate: Date
    let rotationPrimaryDays: Int
    let rotationAlternateDays: Int
    let oneNightOverride: OneNightScheduleOverride?

    init(
        startSeconds: Int,
        bedSeconds: Int,
        activeWeekdays: Set<Int>,
        alternateScheduleEnabled: Bool,
        alternateWeekdays: Set<Int>,
        alternateStartSeconds: Int,
        alternateBedSeconds: Int,
        alternatePattern: AlternateSchedulePattern = .selectedWeekdays,
        rotationAnchorDate: Date = .distantPast,
        rotationPrimaryDays: Int = 4,
        rotationAlternateDays: Int = 4,
        oneNightOverride: OneNightScheduleOverride? = nil
    ) {
        self.startSeconds = startSeconds
        self.bedSeconds = bedSeconds
        self.activeWeekdays = activeWeekdays
        self.alternateScheduleEnabled = alternateScheduleEnabled
        self.alternateWeekdays = alternateWeekdays
        self.alternateStartSeconds = alternateStartSeconds
        self.alternateBedSeconds = alternateBedSeconds
        self.alternatePattern = alternatePattern
        self.rotationAnchorDate = rotationAnchorDate
        self.rotationPrimaryDays = min(max(rotationPrimaryDays, 1), 28)
        self.rotationAlternateDays = min(max(rotationAlternateDays, 1), 28)
        self.oneNightOverride = oneNightOverride
    }

    static func everyNight(startSeconds: Int, bedSeconds: Int) -> Self {
        Self(
            startSeconds: startSeconds,
            bedSeconds: bedSeconds,
            activeWeekdays: Set(1...7),
            alternateScheduleEnabled: false,
            alternateWeekdays: [],
            alternateStartSeconds: startSeconds,
            alternateBedSeconds: bedSeconds
        )
    }

    func times(for anchorDay: Date, calendar: Calendar) -> (start: Int, bed: Int)? {
        switch selection(for: anchorDay, calendar: calendar) {
        case .some(.oneNightOverride):
            guard let oneNightOverride else { return nil }
            return (oneNightOverride.startSeconds, oneNightOverride.bedSeconds)
        case .some(.alternate):
            return (alternateStartSeconds, alternateBedSeconds)
        case .some(.primary):
            return (startSeconds, bedSeconds)
        case nil:
            return nil
        }
    }

    func selection(for anchorDay: Date, calendar: Calendar) -> BedtimeScheduleSelection? {
        if let oneNightOverride,
            calendar.isDate(anchorDay, inSameDayAs: oneNightOverride.anchorDate)
        {
            return .oneNightOverride
        }

        let weekday = calendar.component(.weekday, from: anchorDay)
        guard activeWeekdays.contains(weekday) else { return nil }
        if alternateScheduleEnabled, usesAlternateSchedule(on: anchorDay, calendar: calendar) {
            return .alternate
        }
        return .primary
    }

    func usesAlternateSchedule(on anchorDay: Date, calendar: Calendar) -> Bool {
        switch alternatePattern {
        case .selectedWeekdays:
            return alternateWeekdays.contains(calendar.component(.weekday, from: anchorDay))
        case .rotatingCycle:
            let anchor = calendar.startOfDay(for: rotationAnchorDate)
            let day = calendar.startOfDay(for: anchorDay)
            let elapsed = calendar.dateComponents([.day], from: anchor, to: day).day ?? 0
            let cycleLength = rotationPrimaryDays + rotationAlternateDays
            let position = ((elapsed % cycleLength) + cycleLength) % cycleLength
            return position >= rotationPrimaryDays
        }
    }
}

/// Performs all scheduling in a real calendar and time zone.
///
/// The original app shifted `Date` values by the GMT offset manually, which applied
/// the offset twice and failed around midnight and daylight-saving changes. This
/// calculator works with local wall-clock components and lets Calendar resolve DST.
struct ScheduleCalculator: Sendable {
    private var calendar: Calendar

    init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
    }

    func window(
        containingOrAfter date: Date,
        startSeconds: Int,
        bedSeconds: Int
    ) -> BedtimeWindow? {
        window(
            containingOrAfter: date,
            schedule: .everyNight(startSeconds: startSeconds, bedSeconds: bedSeconds)
        )
    }

    func window(
        containingOrAfter date: Date,
        schedule: WeeklyBedtimeSchedule
    ) -> BedtimeWindow? {
        windows(around: date, schedule: schedule)
            .first { $0.contains(date) || $0.start > date }
    }

    func nextNudge(
        after date: Date,
        interval: TimeInterval,
        startSeconds: Int,
        bedSeconds: Int
    ) -> ScheduledNudge? {
        nextNudge(
            after: date,
            interval: interval,
            schedule: .everyNight(startSeconds: startSeconds, bedSeconds: bedSeconds)
        )
    }

    func nextNudge(
        after date: Date,
        interval: TimeInterval,
        schedule: WeeklyBedtimeSchedule
    ) -> ScheduledNudge? {
        let safeInterval = max(interval, 1)
        let candidateWindows = windows(around: date, schedule: schedule)

        if let activeWindow = candidateWindows.first(where: { $0.contains(date) }) {
            let candidate = date.addingTimeInterval(safeInterval)
            if candidate < activeWindow.end {
                return ScheduledNudge(fireDate: candidate, window: activeWindow)
            }
        }

        guard let futureWindow = candidateWindows.first(where: { $0.start > date }) else {
            return nil
        }

        let delay = min(safeInterval, max(futureWindow.duration / 2, 1))
        return ScheduledNudge(
            fireDate: futureWindow.start.addingTimeInterval(delay),
            window: futureWindow
        )
    }

    static func intervalRange(frequencyMinutes: Double) -> ClosedRange<TimeInterval> {
        let finiteFrequency =
            frequencyMinutes.isFinite
            ? frequencyMinutes
            : AppSettings.defaultFrequencyMinutes
        let base = min(max(finiteFrequency, 1), 30) * 60
        return base...(base * 1.7)
    }

    private func windows(
        around date: Date,
        schedule: WeeklyBedtimeSchedule
    ) -> [BedtimeWindow] {
        let startOfReferenceDay = calendar.startOfDay(for: date)

        return (-1...8).compactMap { dayOffset in
            guard
                let anchorDay = calendar.date(
                    byAdding: .day,
                    value: dayOffset,
                    to: startOfReferenceDay
                ),
                let times = schedule.times(for: anchorDay, calendar: calendar),
                // Equal begin and bed times are not a 24-hour window; that night has no window.
                times.bed != times.start,
                let start = wallClockDate(seconds: times.start, on: anchorDay)
            else {
                return nil
            }

            let crossesMidnight = times.bed < times.start
            guard
                let endDay = crossesMidnight
                    ? calendar.date(byAdding: .day, value: 1, to: anchorDay)
                    : anchorDay,
                let end = wallClockDate(seconds: times.bed, on: endDay)
            else {
                return nil
            }
            if end > start {
                return BedtimeWindow(start: start, end: end)
            }

            // A begin time inside a spring-forward gap is pushed forward by the whole gap,
            // which can pass a bedtime just after the gap. Begin at the first valid instant.
            guard
                let gapStart = WallClockDateResolver.date(
                    seconds: times.start,
                    on: anchorDay,
                    calendar: calendar,
                    matchingPolicy: .nextTime
                ),
                end > gapStart
            else {
                return nil
            }
            return BedtimeWindow(start: gapStart, end: end)
        }
        .sorted { $0.start < $1.start }
    }

    private func wallClockDate(seconds: Int, on day: Date) -> Date? {
        WallClockDateResolver.date(seconds: seconds, on: day, calendar: calendar)
    }
}

@MainActor
protocol VisualNotificationDelivering: AnyObject {
    func deliverVisualNudge(count: Int, personality: ButlerPersonality?)
    func clearVisualNudges()
}

struct ProgressiveState: Equatable, Sendable {
    private(set) var base: ButlerPersonality
    private(set) var current: ButlerPersonality
    private(set) var nudgeCount = 0
    private(set) var escalationThreshold: Int

    init(base: ButlerPersonality, escalationThreshold: Int = 2) {
        self.base = base
        current = base
        self.escalationThreshold = Self.clampThreshold(escalationThreshold)
    }

    mutating func reset(base: ButlerPersonality, escalationThreshold: Int) {
        self.base = base
        current = base
        nudgeCount = 0
        self.escalationThreshold = Self.clampThreshold(escalationThreshold)
    }

    mutating func recordNudge(progressive: Bool, nextThreshold: Int) {
        guard progressive else {
            current = base
            nudgeCount = 0
            return
        }

        nudgeCount += 1
        guard nudgeCount >= escalationThreshold else { return }

        current = current.escalated
        nudgeCount = 0
        escalationThreshold = Self.clampThreshold(nextThreshold)
    }

    private static func clampThreshold(_ value: Int) -> Int {
        min(max(value, 2), 3)
    }
}

@MainActor
final class ButlerTimer: NSObject, ObservableObject {
    @Published private(set) var nextNudge: Date?
    @Published private(set) var nextPersonality: ButlerPersonality
    @Published private(set) var lastEvent = "Schedule is active."

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "BeddyButler",
        category: "scheduler"
    )
    private let settings: AppSettings
    private let audioPlayer: any AudioPlaying
    private let now: () -> Date
    private let intervalProvider: (ClosedRange<TimeInterval>) -> TimeInterval
    private let escalationProvider: () -> Int
    private weak var visualNotifier: (any VisualNotificationDelivering)?

    private var progression: ProgressiveState
    private var progressionWindowStart: Date?
    private var scheduledWindow: BedtimeWindow?
    private var scheduledMutedUntil: Date?
    private(set) var timer: Timer?
    /// Fires at the next window start, window end or pause end so clock-dependent UI refreshes.
    private(set) var boundaryTimer: Timer?

    var canSnooze: Bool {
        guard settings.hasActivatedSchedule, !settings.isMuted(at: now()) else { return false }
        return activeWindow(at: now()) != nil
    }

    /// A short snooze inside tonight's window. A whole-night pause, or a snooze that
    /// reaches bedtime, counts as paused instead.
    var isSnoozed: Bool {
        let currentDate = now()
        guard settings.hasActivatedSchedule, settings.isMuted(at: currentDate), !hasFinishedTonight,
            let mutedUntil = settings.mutedUntil,
            let window = activeWindow(at: currentDate)
        else {
            return false
        }
        return mutedUntil < window.end
    }

    var hasFinishedTonight: Bool {
        settings.finishedWindowEnd == settings.mutedUntil && settings.finishedWindowEnd != nil
            && settings.isMuted(at: now())
    }

    var visualNudgePending: Bool { settings.pendingVisualNudgeCount > 0 }
    var pendingVisualNudgeCount: Int { settings.pendingVisualNudgeCount }

    init(
        settings: AppSettings,
        audioPlayer: any AudioPlaying,
        now: @escaping () -> Date = Date.init,
        intervalProvider: @escaping (ClosedRange<TimeInterval>) -> TimeInterval = {
            Double.random(in: $0)
        },
        escalationProvider: @escaping () -> Int = {
            Int.random(in: 2...3)
        },
        visualNotifier: (any VisualNotificationDelivering)? = nil
    ) {
        self.settings = settings
        self.audioPlayer = audioPlayer
        self.now = now
        self.intervalProvider = intervalProvider
        self.escalationProvider = escalationProvider
        self.visualNotifier = visualNotifier
        progression = ProgressiveState(
            base: settings.personality,
            escalationThreshold: escalationProvider()
        )
        nextPersonality = settings.personality
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsDidChange),
            name: .beddySettingsDidChange,
            object: settings
        )
        recalculate()
    }

    /// Reschedules the next nudge. `preservingPendingNudge` keeps an already drawn nudge
    /// when nothing that decides it has changed, so opening a window or adjusting an
    /// unrelated setting does not push the nudge back.
    func recalculate(preservingPendingNudge: Bool = false) {
        guard settings.hasActivatedSchedule else {
            invalidateTimers()
            timer = nil
            boundaryTimer = nil
            nextNudge = nil
            scheduledWindow = nil
            lastEvent = ""
            NotificationCenter.default.post(name: .beddyScheduleDidChange, object: self)
            return
        }

        let currentDate = now()
        settings.clearExpiredMute(at: currentDate)
        settings.clearExpiredTonightOverride(at: currentDate)

        let calculator = ScheduleCalculator(calendar: .autoupdatingCurrent)
        let schedule = weeklySchedule
        let intervalRange = ScheduleCalculator.intervalRange(
            frequencyMinutes: settings.frequencyMinutes
        )
        followWidenedWindow(at: currentDate, calculator: calculator, schedule: schedule)

        let pendingNudge =
            preservingPendingNudge
            ? reusablePendingNudge(
                at: currentDate,
                calculator: calculator,
                schedule: schedule,
                intervalRange: intervalRange
            ) : nil
        let nudge: ScheduledNudge?
        if let pendingNudge {
            nudge = pendingNudge
        } else if let mutedUntil = settings.mutedUntil,
            mutedUntil > currentDate,
            let resumeWindow = calculator.window(
                containingOrAfter: mutedUntil,
                schedule: schedule
            ),
            resumeWindow.contains(mutedUntil)
        {
            // A short snooze resumes at the promised time. A whole-night pause ends
            // exactly at the window boundary and therefore schedules the next night.
            nudge = ScheduledNudge(fireDate: mutedUntil, window: resumeWindow)
        } else {
            let schedulingDate = settings.mutedUntil.flatMap { $0 > currentDate ? $0 : nil } ?? currentDate
            nudge = calculator.nextNudge(
                after: schedulingDate,
                interval: intervalProvider(intervalRange),
                schedule: schedule
            )
        }

        guard let nudge else {
            timer?.invalidate()
            timer = nil
            nextNudge = nil
            scheduledWindow = nil
            lastEvent = "No valid bedtime window is configured."
            scheduleBoundaryRefresh(after: currentDate, calculator: calculator, schedule: schedule)
            NotificationCenter.default.post(name: .beddyScheduleDidChange, object: self)
            return
        }

        let baseChanged = progression.base != settings.personality
        let windowChanged = progressionWindowStart != nudge.window.start
        if baseChanged || windowChanged || !settings.progressiveMode {
            progression.reset(
                base: settings.personality,
                escalationThreshold: escalationProvider()
            )
            progressionWindowStart = nudge.window.start
        }

        nextPersonality =
            settings.progressiveMode
            ? progression.current.capped(at: settings.effectiveMaximumPersonality) : settings.personality
        nextNudge = nudge.fireDate
        scheduledWindow = nudge.window
        scheduledMutedUntil = settings.mutedUntil

        if pendingNudge == nil {
            let nextTimer = Timer(
                fireAt: nudge.fireDate,
                interval: 0,
                target: self,
                selector: #selector(timerDidFire),
                userInfo: nil,
                repeats: false
            )
            nextTimer.tolerance = min(
                30,
                max(nudge.fireDate.timeIntervalSince(currentDate), 0) * 0.05
            )
            RunLoop.main.add(nextTimer, forMode: .common)
            // Invalidate here too, in case anything scheduled a timer while this call ran.
            timer?.invalidate()
            timer = nextTimer
        }
        scheduleBoundaryRefresh(after: currentDate, calculator: calculator, schedule: schedule)

        logger.debug("Scheduled next nudge for \(nudge.fireDate, privacy: .public)")
        NotificationCenter.default.post(name: .beddyScheduleDidChange, object: self)
    }

    func snooze(minutes: Int? = nil) {
        guard settings.hasActivatedSchedule else { return }
        let currentDate = now()
        guard let window = activeWindow(at: currentDate) else {
            lastEvent = "Snooze is available during your bedtime window."
            NotificationCenter.default.post(name: .beddyScheduleDidChange, object: self)
            return
        }

        // A stale notification's Snooze must not shorten a pause that is already running.
        if let mutedUntil = settings.mutedUntil, settings.isMuted(at: currentDate) {
            lastEvent =
                isSnoozed
                ? "Snoozed until \(LocalizedScheduleText.time(mutedUntil))."
                : "Nudges are paused for this bedtime window."
            NotificationCenter.default.post(name: .beddyScheduleDidChange, object: self)
            return
        }

        let requestedResume = currentDate.addingTimeInterval(
            TimeInterval(min(max(minutes ?? settings.snoozeMinutes, 1), 1440) * 60))
        audioPlayer.stop()
        if requestedResume < window.end {
            settings.mute(until: requestedResume)
            lastEvent = "Snoozed until \(LocalizedScheduleText.time(requestedResume))."
        } else {
            settings.mute(until: window.end, wholeWindow: true)
            lastEvent = "Snooze reaches bedtime, so nudges are paused for tonight."
        }
    }

    func muteForCurrentWindow() {
        guard settings.hasActivatedSchedule else { return }
        let currentDate = now()
        let calculator = ScheduleCalculator(calendar: .autoupdatingCurrent)

        guard
            let window = calculator.window(
                containingOrAfter: currentDate,
                schedule: weeklySchedule
            )
        else {
            lastEvent = "No bedtime window is available to mute."
            return
        }

        settings.mute(until: window.end, wholeWindow: true)
        audioPlayer.stop()
        visualNotifier?.clearVisualNudges()
        lastEvent = "Nudges are paused for this bedtime window."
    }

    func finishTonight() {
        guard settings.hasActivatedSchedule else { return }
        guard !hasFinishedTonight, canSnooze || isSnoozed, let window = activeWindow(at: now()) else {
            // The button was stale (for example, bedtime has passed). Refresh so it disappears.
            objectWillChange.send()
            NotificationCenter.default.post(name: .beddyScheduleDidChange, object: self)
            return
        }
        settings.finishWindow(until: window.end)
        audioPlayer.stop()
        visualNotifier?.clearVisualNudges()
        lastEvent = "Good night."
    }

    func undoFinishTonight() {
        if settings.undoFinishedWindow(at: now()) {
            lastEvent = "Nudges resumed."
        }
    }

    /// Resumes from any pause. After "I'm heading to bed" this is the same as Undo, so the
    /// badges set aside by finishing are restored rather than discarded.
    func resumeNudges() {
        if hasFinishedTonight {
            settings.undoFinishedWindow(at: now())
        } else {
            settings.resumeNudges()
        }
        lastEvent = "Nudges resumed."
    }

    func previewSelectedNudge() {
        previewNudge(settings.personality)
    }

    func previewNudge(_ personality: ButlerPersonality) {
        var messages: [String] = []
        if settings.nudgeDelivery.includesSound {
            do {
                let clip = try audioPlayer.play(personality, volume: settings.voiceVolume)
                messages.append("Previewed \(personality.indefiniteArticle) \(personality.title) reminder.")
                logger.debug("Previewed \(clip.lastPathComponent, privacy: .public)")
            } catch {
                messages.append(error.localizedDescription)
                logger.error("Preview failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        if settings.nudgeDelivery.includesVisual, !hasFinishedTonight {
            recordVisualNudge(
                personality: settings.nudgeDelivery.includesSound ? personality : nil,
                preview: true
            )
            messages.append("Visual badge preview is waiting in the menu bar.")
        }
        if !messages.isEmpty {
            lastEvent = messages.joined(separator: " ")
        }
        NotificationCenter.default.post(name: .beddyScheduleDidChange, object: self)
    }

    func acknowledgeVisualNudge() {
        guard visualNudgePending else { return }
        settings.clearVisualNudges()
        audioPlayer.stop()
        visualNotifier?.clearVisualNudges()
        lastEvent = "Visual nudge acknowledged."
        NotificationCenter.default.post(name: .beddyScheduleDidChange, object: self)
    }

    /// Invalidates both timers, for example before the Mac sleeps. Wake recalculates.
    func invalidateTimers() {
        timer?.invalidate()
        boundaryTimer?.invalidate()
    }

    /// Republishes clock-dependent state (window start or end, a pause ending) without
    /// drawing a new nudge interval.
    func refreshTimeDependentState() {
        let currentDate = now()
        settings.clearExpiredMute(at: currentDate)
        if settings.hasActivatedSchedule {
            scheduleBoundaryRefresh(
                after: currentDate,
                calculator: ScheduleCalculator(calendar: .autoupdatingCurrent),
                schedule: weeklySchedule
            )
        }
        objectWillChange.send()
        NotificationCenter.default.post(name: .beddyScheduleDidChange, object: self)
    }

    @objc private func settingsDidChange() {
        recalculate(preservingPendingNudge: true)
    }

    @objc private func timerDidFire() {
        handleTimerFire()
    }

    func handleTimerFire() {
        let currentDate = now()
        guard !settings.isMuted(at: currentDate) else {
            recalculate()
            return
        }
        guard let scheduledWindow, scheduledWindow.contains(currentDate) else {
            recalculate()
            return
        }

        deliverNudge()

        progression.recordNudge(
            progressive: settings.progressiveMode && settings.nudgeDelivery.includesSound,
            nextThreshold: escalationProvider()
        )
        recalculate()
    }

    func deliverNudge() {
        guard settings.hasActivatedSchedule else { return }
        let personality =
            settings.progressiveMode
            ? progression.current.capped(at: settings.effectiveMaximumPersonality) : settings.personality
        var messages: [String] = []

        if settings.nudgeDelivery.includesSound {
            do {
                let clip = try audioPlayer.play(personality, volume: settings.voiceVolume)
                messages.append("\(personality.title) played at \(LocalizedScheduleText.time(now())).")
                logger.info("Played \(clip.lastPathComponent, privacy: .public)")
            } catch {
                messages.append(error.localizedDescription)
                logger.error("Nudge playback failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        if settings.nudgeDelivery.includesVisual {
            recordVisualNudge(personality: settings.nudgeDelivery.includesSound ? personality : nil)
            messages.append("Visual bedtime badge is waiting in the menu bar.")
        }

        lastEvent = messages.joined(separator: " ")
        NotificationCenter.default.post(name: .beddyScheduleDidChange, object: self)
    }

    private func activeWindow(at date: Date) -> BedtimeWindow? {
        let calculator = ScheduleCalculator(calendar: .autoupdatingCurrent)
        guard
            let window = calculator.window(
                containingOrAfter: date,
                schedule: weeklySchedule
            ),
            window.contains(date)
        else {
            return nil
        }
        return window
    }

    private var weeklySchedule: WeeklyBedtimeSchedule {
        WeeklyBedtimeSchedule(
            startSeconds: settings.startSeconds,
            bedSeconds: settings.bedSeconds,
            activeWeekdays: settings.activeWeekdays,
            alternateScheduleEnabled: settings.alternateScheduleEnabled,
            alternateWeekdays: settings.alternateScheduleWeekdays,
            alternateStartSeconds: settings.alternateStartSeconds,
            alternateBedSeconds: settings.alternateBedSeconds,
            alternatePattern: settings.alternateSchedulePattern,
            rotationAnchorDate: settings.rotationAnchorDate,
            rotationPrimaryDays: settings.rotationPrimaryDays,
            rotationAlternateDays: settings.rotationAlternateDays,
            oneNightOverride: settings.tonightOverrideDate.map {
                OneNightScheduleOverride(
                    anchorDate: $0,
                    startSeconds: settings.tonightOverrideStartSeconds,
                    bedSeconds: settings.tonightOverrideBedSeconds
                )
            }
        )
    }

    private func reusablePendingNudge(
        at currentDate: Date,
        calculator: ScheduleCalculator,
        schedule: WeeklyBedtimeSchedule,
        intervalRange: ClosedRange<TimeInterval>
    ) -> ScheduledNudge? {
        guard timer?.isValid == true,
            let pendingDate = nextNudge,
            let pendingWindow = scheduledWindow,
            pendingDate > currentDate,
            // A shorter frequency or a backward clock change draws again.
            pendingDate <= max(currentDate, pendingWindow.start).addingTimeInterval(intervalRange.upperBound),
            settings.mutedUntil == nil,
            scheduledMutedUntil == nil,
            calculator.window(containingOrAfter: currentDate, schedule: schedule) == pendingWindow
        else {
            return nil
        }
        return ScheduledNudge(fireDate: pendingDate, window: pendingWindow)
    }

    /// Keeps a whole-window pause or finish lasting until bedtime after bedtime moves later.
    private func followWidenedWindow(
        at currentDate: Date,
        calculator: ScheduleCalculator,
        schedule: WeeklyBedtimeSchedule
    ) {
        guard settings.mutesWholeWindow,
            let mutedUntil = settings.mutedUntil,
            mutedUntil > currentDate,
            let window = calculator.window(containingOrAfter: currentDate, schedule: schedule),
            window.start < mutedUntil,
            mutedUntil < window.end
        else {
            return
        }
        settings.extendWholeWindowMute(until: window.end)
    }

    private func scheduleBoundaryRefresh(
        after currentDate: Date,
        calculator: ScheduleCalculator,
        schedule: WeeklyBedtimeSchedule
    ) {
        boundaryTimer?.invalidate()
        boundaryTimer = nil
        var boundaries: [Date] = []
        if let window = calculator.window(containingOrAfter: currentDate, schedule: schedule) {
            boundaries.append(window.contains(currentDate) ? window.end : window.start)
        }
        if let mutedUntil = settings.mutedUntil, mutedUntil > currentDate {
            boundaries.append(mutedUntil)
        }
        guard let fireDate = boundaries.min() else { return }
        let nextTimer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshTimeDependentState()
            }
        }
        nextTimer.tolerance = 1
        RunLoop.main.add(nextTimer, forMode: .common)
        boundaryTimer = nextTimer
    }

    private func recordVisualNudge(personality: ButlerPersonality?, preview: Bool = false) {
        if preview {
            settings.recordVisualNudgePreview(at: now())
        } else {
            settings.recordVisualNudge(at: now())
        }
        if settings.notificationAlertsEnabled {
            visualNotifier?.deliverVisualNudge(
                count: settings.pendingVisualNudgeCount,
                personality: personality
            )
        }
    }
}
