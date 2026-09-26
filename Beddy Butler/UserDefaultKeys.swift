import Combine
import Foundation

enum NudgeDelivery: String, CaseIterable, Identifiable, Codable, Sendable {
    case sound
    case visual
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sound: "Sound"
        case .visual: "Visual"
        case .both: "Both"
        }
    }

    var includesSound: Bool { self != .visual }
    var includesVisual: Bool { self != .sound }

    var guidance: String {
        switch self {
        case .sound:
            "Play a spoken bedtime reminder."
        case .visual:
            "Show a persistent badge in the menu bar until you acknowledge it."
        case .both:
            "Play the reminder and keep a visual badge waiting in the menu bar."
        }
    }

    init(storedValue: String?) {
        self = Self(rawValue: storedValue?.lowercased() ?? "") ?? .sound
    }
}

enum AlternateSchedulePattern: String, CaseIterable, Identifiable, Codable, Sendable {
    case selectedWeekdays
    case rotatingCycle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .selectedWeekdays: "Selected weekdays"
        case .rotatingCycle: "Rotating cycle"
        }
    }

    init(storedValue: String?) {
        self = Self(rawValue: storedValue ?? "") ?? .selectedWeekdays
    }
}

enum UserDefaultKeys: String, CaseIterable {
    case bedTimeValue
    case startTimeValue
    case runStartup
    case selectedSound
    case frequency
    case isMuted
    case progressive
    case mutedUntil
    case voiceVolume
    case nudgeDelivery
    case activeWeekdays
    case alternateScheduleEnabled
    case alternateScheduleWeekdays
    case alternateStartTimeValue
    case alternateBedTimeValue
    case primaryScheduleName
    case alternateScheduleName
    case alternateSchedulePattern
    case rotationAnchorDate
    case rotationPrimaryDays
    case rotationAlternateDays
    case tonightOverrideDate
    case tonightOverrideStartTimeValue
    case tonightOverrideBedTimeValue
    // Legacy Swift 6 revival keys, migrated to the neutral alternate-schedule model.
    case separateWeekendSchedule
    case weekendStartTimeValue
    case weekendBedTimeValue
    case notificationAlertsEnabled
    case pendingVisualNudgeCount
    case lastVisualNudgeAt
    case onboardingVersion
    case hasActivatedSchedule
    case snoozeMinutes
    case maximumPersonality
    case finishedWindowEnd
    case finishedBadgeCount
    case finishedBadgeDate
    case mutedWholeWindow
}

extension Notification.Name {
    static let beddySettingsDidChange = Notification.Name("BeddyButler.settingsDidChange")
    static let beddyScheduleDidChange = Notification.Name("BeddyButler.scheduleDidChange")
    static let beddyWelcomeGuideRequested = Notification.Name("BeddyButler.welcomeGuideRequested")
}

/// A user-selected calendar day whose identity survives time-zone changes.
struct LocalCalendarDate: Equatable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(date: Date, calendar: Calendar = .autoupdatingCurrent) {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let components = gregorian.dateComponents([.year, .month, .day], from: date)
        year = components.year ?? 1970
        month = components.month ?? 1
        day = components.day ?? 1
    }

    init?(storedValue: String) {
        let components = storedValue.split(separator: "-", omittingEmptySubsequences: false)
        guard components.count == 3,
            let year = Int(components[0]),
            let month = Int(components[1]),
            let day = Int(components[2]),
            (1...12).contains(month),
            (1...31).contains(day)
        else {
            return nil
        }
        self.year = year
        self.month = month
        self.day = day
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        guard let date = self.date(calendar: gregorian) else {
            return nil
        }
        let validated = gregorian.dateComponents([.year, .month, .day], from: date)
        guard validated.year == year, validated.month == month, validated.day == day else {
            return nil
        }
    }

    var storedValue: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    func date(calendar: Calendar = .autoupdatingCurrent) -> Date? {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        return gregorian.date(from: DateComponents(year: year, month: month, day: day))
    }
}

/// The persisted preferences shared by the menu, preferences window, and scheduler.
///
/// Start and bed times remain stored as seconds after local midnight. This preserves
/// compatibility with the original releases while avoiding their manual GMT offsets.
@MainActor
final class AppSettings: ObservableObject {
    nonisolated static let secondsPerDay = 86_400

    nonisolated static let defaultStartSeconds = 21 * 3_600 + 30 * 60
    nonisolated static let defaultBedSeconds = 23 * 3_600
    nonisolated static let defaultFrequencyMinutes = 8.0
    nonisolated static let defaultVoiceVolume = 0.8
    nonisolated static let currentOnboardingVersion = 1

    @Published private(set) var startSeconds: Int
    @Published private(set) var bedSeconds: Int
    @Published private(set) var snoozeMinutes: Int
    @Published private(set) var maximumPersonality: ButlerPersonality
    @Published private(set) var frequencyMinutes: Double
    @Published private(set) var personality: ButlerPersonality
    @Published private(set) var progressiveMode: Bool
    @Published private(set) var mutedUntil: Date?
    @Published private(set) var finishedWindowEnd: Date?
    /// True when `mutedUntil` marks the end of a whole bedtime window rather than a short snooze.
    private(set) var mutedWholeWindow: Bool
    private var finishedBadgeCount: Int
    private var finishedBadgeDate: Date?
    @Published private(set) var voiceVolume: Double
    @Published private(set) var nudgeDelivery: NudgeDelivery
    @Published private(set) var activeWeekdays: Set<Int>
    @Published private(set) var alternateScheduleEnabled: Bool
    @Published private(set) var alternateScheduleWeekdays: Set<Int>
    @Published private(set) var alternateStartSeconds: Int
    @Published private(set) var alternateBedSeconds: Int
    @Published private(set) var primaryScheduleName: String
    @Published private(set) var alternateScheduleName: String
    @Published private(set) var alternateSchedulePattern: AlternateSchedulePattern
    @Published private var rotationAnchorCalendarDate: LocalCalendarDate
    @Published private(set) var rotationPrimaryDays: Int
    @Published private(set) var rotationAlternateDays: Int
    @Published private var tonightOverrideCalendarDate: LocalCalendarDate?
    @Published private(set) var tonightOverrideStartSeconds: Int
    @Published private(set) var tonightOverrideBedSeconds: Int
    @Published private(set) var notificationAlertsEnabled: Bool
    @Published private(set) var pendingVisualNudgeCount: Int
    @Published private(set) var lastVisualNudgeAt: Date?
    @Published private(set) var hasActivatedSchedule: Bool = false
    @Published private(set) var hasCompletedOnboarding: Bool

    private let defaults: UserDefaults

    var rotationAnchorDate: Date {
        rotationAnchorCalendarDate.date() ?? Date()
    }

    var tonightOverrideDate: Date? {
        tonightOverrideCalendarDate?.date()
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let hadExistingConfiguration = Self.hasExistingConfiguration(in: defaults)
        startSeconds = Self.readSeconds(
            key: .startTimeValue,
            from: defaults,
            fallback: Self.defaultStartSeconds
        )
        bedSeconds = Self.readSeconds(
            key: .bedTimeValue,
            from: defaults,
            fallback: Self.defaultBedSeconds
        )

        let storedSnooze = defaults.integer(forKey: UserDefaultKeys.snoozeMinutes.rawValue)
        snoozeMinutes = [10, 20, 30, 60].contains(storedSnooze) ? storedSnooze : 30
        maximumPersonality =
            defaults.string(forKey: UserDefaultKeys.maximumPersonality.rawValue)
            .map { ButlerPersonality(storedValue: $0) } ?? .zombie
        let storedFrequency = defaults.object(forKey: UserDefaultKeys.frequency.rawValue) as? NSNumber
        frequencyMinutes = Self.clampFrequency(storedFrequency?.doubleValue ?? Self.defaultFrequencyMinutes)

        let storedPersonality = defaults.string(forKey: UserDefaultKeys.selectedSound.rawValue)
        personality = ButlerPersonality(storedValue: storedPersonality)
        progressiveMode = defaults.object(forKey: UserDefaultKeys.progressive.rawValue) as? Bool ?? false
        mutedUntil = defaults.object(forKey: UserDefaultKeys.mutedUntil.rawValue) as? Date
        finishedWindowEnd = defaults.object(forKey: UserDefaultKeys.finishedWindowEnd.rawValue) as? Date
        mutedWholeWindow = defaults.bool(forKey: UserDefaultKeys.mutedWholeWindow.rawValue)
        finishedBadgeCount = Self.clampVisualNudgeCount(
            defaults.integer(forKey: UserDefaultKeys.finishedBadgeCount.rawValue))
        finishedBadgeDate = defaults.object(forKey: UserDefaultKeys.finishedBadgeDate.rawValue) as? Date
        let storedVolume = defaults.object(forKey: UserDefaultKeys.voiceVolume.rawValue) as? NSNumber
        voiceVolume = Self.clampVolume(storedVolume?.doubleValue ?? Self.defaultVoiceVolume)
        nudgeDelivery = NudgeDelivery(
            storedValue: defaults.string(forKey: UserDefaultKeys.nudgeDelivery.rawValue)
        )
        activeWeekdays = Self.readActiveWeekdays(from: defaults)
        alternateScheduleEnabled = Self.readMigratedBool(
            key: .alternateScheduleEnabled,
            legacyKey: .separateWeekendSchedule,
            from: defaults,
            fallback: false
        )
        alternateScheduleWeekdays = Self.readAlternateScheduleWeekdays(from: defaults)
        alternateStartSeconds = Self.readMigratedSeconds(
            key: .alternateStartTimeValue,
            legacyKey: .weekendStartTimeValue,
            from: defaults,
            fallback: Self.defaultStartSeconds
        )
        alternateBedSeconds = Self.readMigratedSeconds(
            key: .alternateBedTimeValue,
            legacyKey: .weekendBedTimeValue,
            from: defaults,
            fallback: Self.defaultBedSeconds
        )
        primaryScheduleName = Self.readScheduleName(
            defaults.string(forKey: UserDefaultKeys.primaryScheduleName.rawValue),
            fallback: "Regular"
        )
        alternateScheduleName = Self.readScheduleName(
            defaults.string(forKey: UserDefaultKeys.alternateScheduleName.rawValue),
            fallback: "Alternate"
        )
        alternateSchedulePattern = AlternateSchedulePattern(
            storedValue: defaults.string(forKey: UserDefaultKeys.alternateSchedulePattern.rawValue)
        )
        rotationAnchorCalendarDate = Self.readCalendarDate(
            key: .rotationAnchorDate,
            from: defaults,
            fallback: Date()
        )
        rotationPrimaryDays = Self.clampCycleDays(
            (defaults.object(forKey: UserDefaultKeys.rotationPrimaryDays.rawValue) as? NSNumber)?.intValue ?? 4
        )
        rotationAlternateDays = Self.clampCycleDays(
            (defaults.object(forKey: UserDefaultKeys.rotationAlternateDays.rawValue) as? NSNumber)?.intValue ?? 4
        )
        tonightOverrideCalendarDate = Self.readOptionalCalendarDate(
            key: .tonightOverrideDate,
            from: defaults
        )
        tonightOverrideStartSeconds = Self.readSeconds(
            key: .tonightOverrideStartTimeValue,
            from: defaults,
            fallback: Self.defaultStartSeconds
        )
        tonightOverrideBedSeconds = Self.readSeconds(
            key: .tonightOverrideBedTimeValue,
            from: defaults,
            fallback: Self.defaultBedSeconds
        )
        notificationAlertsEnabled =
            defaults.object(forKey: UserDefaultKeys.notificationAlertsEnabled.rawValue) as? Bool ?? false
        let storedVisualCount =
            defaults.object(forKey: UserDefaultKeys.pendingVisualNudgeCount.rawValue) as? NSNumber
        pendingVisualNudgeCount = Self.clampVisualNudgeCount(storedVisualCount?.intValue ?? 0)
        lastVisualNudgeAt = defaults.object(forKey: UserDefaultKeys.lastVisualNudgeAt.rawValue) as? Date

        if let storedVersion = defaults.object(forKey: UserDefaultKeys.onboardingVersion.rawValue) as? NSNumber {
            hasCompletedOnboarding = storedVersion.intValue >= Self.currentOnboardingVersion
        } else {
            // Anyone with settings from a historical release has already configured the app.
            hasCompletedOnboarding = hadExistingConfiguration
            if !hadExistingConfiguration {
                defaults.set(0, forKey: UserDefaultKeys.onboardingVersion.rawValue)
            }
        }

        // Neither replaying the welcome guide nor updating from a release without the Start
        // step (2.0.2 and earlier) may turn off an established routine.
        let alreadyCompleted = hasCompletedOnboarding
        hasActivatedSchedule =
            (defaults.object(forKey: UserDefaultKeys.hasActivatedSchedule.rawValue) as? Bool)
            ?? (alreadyCompleted || hadExistingConfiguration)
        defaults.set(hasActivatedSchedule, forKey: UserDefaultKeys.hasActivatedSchedule.rawValue)
        persistAll()
    }

    var weeklySchedule: WeeklyBedtimeSchedule {
        weeklySchedule(
            oneNightOverride: tonightOverrideDate.map {
                OneNightScheduleOverride(
                    anchorDate: $0,
                    startSeconds: tonightOverrideStartSeconds,
                    bedSeconds: tonightOverrideBedSeconds
                )
            }
        )
    }

    /// The progressive ceiling, never softer than the selected personality.
    var effectiveMaximumPersonality: ButlerPersonality {
        // `capped(at:)` returns the softer of the two, so this returns the firmer.
        maximumPersonality.capped(at: personality) == maximumPersonality ? personality : maximumPersonality
    }

    private func weeklySchedule(oneNightOverride: OneNightScheduleOverride?) -> WeeklyBedtimeSchedule {
        WeeklyBedtimeSchedule(
            startSeconds: startSeconds,
            bedSeconds: bedSeconds,
            activeWeekdays: activeWeekdays,
            alternateScheduleEnabled: alternateScheduleEnabled,
            alternateWeekdays: alternateScheduleWeekdays,
            alternateStartSeconds: alternateStartSeconds,
            alternateBedSeconds: alternateBedSeconds,
            alternatePattern: alternateSchedulePattern,
            rotationAnchorDate: rotationAnchorDate,
            rotationPrimaryDays: rotationPrimaryDays,
            rotationAlternateDays: rotationAlternateDays,
            oneNightOverride: oneNightOverride
        )
    }

    func updateSnoozeMinutes(_ value: Int) {
        guard [10, 20, 30, 60].contains(value), value != snoozeMinutes else { return }
        snoozeMinutes = value
        defaults.set(value, forKey: UserDefaultKeys.snoozeMinutes.rawValue)
        announceChange()
    }

    func updateMaximumPersonality(_ value: ButlerPersonality) {
        maximumPersonality = value
        defaults.set(value.rawValue, forKey: UserDefaultKeys.maximumPersonality.rawValue)
        announceChange()
    }

    func updateStartSeconds(_ value: Int) {
        let normalized = Self.clampSeconds(value)
        guard normalized != startSeconds else { return }
        startSeconds = normalized
        defaults.set(Double(normalized), forKey: UserDefaultKeys.startTimeValue.rawValue)
        announceChange()
    }

    func updateBedSeconds(_ value: Int) {
        let normalized = Self.clampSeconds(value)
        guard normalized != bedSeconds else { return }
        bedSeconds = normalized
        defaults.set(Double(normalized), forKey: UserDefaultKeys.bedTimeValue.rawValue)
        announceChange()
    }

    func updateFrequencyMinutes(_ value: Double) {
        let normalized = Self.clampFrequency(value)
        guard normalized != frequencyMinutes else { return }
        frequencyMinutes = normalized
        defaults.set(normalized, forKey: UserDefaultKeys.frequency.rawValue)
        announceChange()
    }

    func updatePersonality(_ value: ButlerPersonality) {
        guard value != personality else { return }
        personality = value
        defaults.set(value.rawValue, forKey: UserDefaultKeys.selectedSound.rawValue)
        announceChange()
    }

    func updateProgressiveMode(_ value: Bool) {
        guard value != progressiveMode else { return }
        progressiveMode = value
        defaults.set(value, forKey: UserDefaultKeys.progressive.rawValue)
        announceChange()
    }

    func updateVoiceVolume(_ value: Double) {
        let normalized = Self.clampVolume(value)
        guard normalized != voiceVolume else { return }
        voiceVolume = normalized
        defaults.set(normalized, forKey: UserDefaultKeys.voiceVolume.rawValue)
        announceChange()
    }

    func updateNudgeDelivery(_ value: NudgeDelivery) {
        guard value != nudgeDelivery else { return }
        nudgeDelivery = value
        defaults.set(value.rawValue, forKey: UserDefaultKeys.nudgeDelivery.rawValue)
        announceChange()
    }

    func updateActiveWeekday(_ weekday: Int, isActive: Bool) {
        guard (1...7).contains(weekday) else { return }
        var updated = activeWeekdays
        if isActive {
            updated.insert(weekday)
        } else {
            updated.remove(weekday)
        }
        guard updated != activeWeekdays else { return }
        activeWeekdays = updated
        defaults.set(updated.sorted(), forKey: UserDefaultKeys.activeWeekdays.rawValue)
        announceChange()
    }

    func updateAlternateScheduleEnabled(_ value: Bool) {
        guard value != alternateScheduleEnabled else { return }
        alternateScheduleEnabled = value
        defaults.set(value, forKey: UserDefaultKeys.alternateScheduleEnabled.rawValue)
        announceChange()
    }

    func updateAlternateScheduleWeekday(_ weekday: Int, isSelected: Bool) {
        guard (1...7).contains(weekday) else { return }
        var updated = alternateScheduleWeekdays
        if isSelected {
            updated.insert(weekday)
        } else {
            updated.remove(weekday)
        }
        guard updated != alternateScheduleWeekdays else { return }
        alternateScheduleWeekdays = updated
        defaults.set(updated.sorted(), forKey: UserDefaultKeys.alternateScheduleWeekdays.rawValue)
        announceChange()
    }

    func updateAlternateStartSeconds(_ value: Int) {
        let normalized = Self.clampSeconds(value)
        guard normalized != alternateStartSeconds else { return }
        alternateStartSeconds = normalized
        defaults.set(Double(normalized), forKey: UserDefaultKeys.alternateStartTimeValue.rawValue)
        announceChange()
    }

    func updateAlternateBedSeconds(_ value: Int) {
        let normalized = Self.clampSeconds(value)
        guard normalized != alternateBedSeconds else { return }
        alternateBedSeconds = normalized
        defaults.set(Double(normalized), forKey: UserDefaultKeys.alternateBedTimeValue.rawValue)
        announceChange()
    }

    @discardableResult
    func updatePrimaryScheduleName(_ value: String) -> String {
        let normalized = Self.readScheduleName(value, fallback: "Regular")
        guard normalized != primaryScheduleName else { return normalized }
        primaryScheduleName = normalized
        defaults.set(normalized, forKey: UserDefaultKeys.primaryScheduleName.rawValue)
        announceChange()
        return normalized
    }

    @discardableResult
    func updateAlternateScheduleName(_ value: String) -> String {
        let normalized = Self.readScheduleName(value, fallback: "Alternate")
        guard normalized != alternateScheduleName else { return normalized }
        alternateScheduleName = normalized
        defaults.set(normalized, forKey: UserDefaultKeys.alternateScheduleName.rawValue)
        announceChange()
        return normalized
    }

    func updateAlternateSchedulePattern(_ value: AlternateSchedulePattern) {
        guard value != alternateSchedulePattern else { return }
        alternateSchedulePattern = value
        defaults.set(value.rawValue, forKey: UserDefaultKeys.alternateSchedulePattern.rawValue)
        announceChange()
    }

    func updateRotationAnchorDate(
        _ value: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        let normalized = LocalCalendarDate(date: value, calendar: calendar)
        guard normalized != rotationAnchorCalendarDate else { return }
        rotationAnchorCalendarDate = normalized
        defaults.set(normalized.storedValue, forKey: UserDefaultKeys.rotationAnchorDate.rawValue)
        announceChange()
    }

    func updateRotationPrimaryDays(_ value: Int) {
        let normalized = Self.clampCycleDays(value)
        guard normalized != rotationPrimaryDays else { return }
        rotationPrimaryDays = normalized
        defaults.set(normalized, forKey: UserDefaultKeys.rotationPrimaryDays.rawValue)
        announceChange()
    }

    func updateRotationAlternateDays(_ value: Int) {
        let normalized = Self.clampCycleDays(value)
        guard normalized != rotationAlternateDays else { return }
        rotationAlternateDays = normalized
        defaults.set(normalized, forKey: UserDefaultKeys.rotationAlternateDays.rawValue)
        announceChange()
    }

    /// Starts a one-night adjustment for the night in progress at `date`.
    ///
    /// Inside a window that began the previous evening, the adjustment belongs to that
    /// night. It starts from the times that night would otherwise use, not the primary times.
    func enableTonightOverride(
        on date: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) {
        let base = weeklySchedule(oneNightOverride: nil)
        let anchorDay: Date
        if let window = ScheduleCalculator(calendar: calendar).window(containingOrAfter: date, schedule: base),
            window.contains(date)
        {
            anchorDay = calendar.startOfDay(for: window.start)
        } else {
            anchorDay = calendar.startOfDay(for: date)
        }
        let seed = base.times(for: anchorDay, calendar: calendar) ?? (startSeconds, bedSeconds)
        let calendarDate = LocalCalendarDate(date: anchorDay, calendar: calendar)
        tonightOverrideCalendarDate = calendarDate
        tonightOverrideStartSeconds = seed.start
        tonightOverrideBedSeconds = seed.bed
        defaults.set(calendarDate.storedValue, forKey: UserDefaultKeys.tonightOverrideDate.rawValue)
        defaults.set(
            Double(tonightOverrideStartSeconds),
            forKey: UserDefaultKeys.tonightOverrideStartTimeValue.rawValue
        )
        defaults.set(
            Double(tonightOverrideBedSeconds),
            forKey: UserDefaultKeys.tonightOverrideBedTimeValue.rawValue
        )
        announceChange()
    }

    func clearTonightOverride() {
        guard tonightOverrideCalendarDate != nil else { return }
        clearTonightOverrideSilently()
        announceChange()
    }

    /// Clears without announcing, so the scheduler can call it mid-recalculation.
    private func clearTonightOverrideSilently() {
        tonightOverrideCalendarDate = nil
        defaults.removeObject(forKey: UserDefaultKeys.tonightOverrideDate.rawValue)
    }

    func updateTonightOverrideStartSeconds(_ value: Int) {
        let normalized = Self.clampSeconds(value)
        guard normalized != tonightOverrideStartSeconds else { return }
        tonightOverrideStartSeconds = normalized
        defaults.set(normalized, forKey: UserDefaultKeys.tonightOverrideStartTimeValue.rawValue)
        announceChange()
    }

    func updateTonightOverrideBedSeconds(_ value: Int) {
        let normalized = Self.clampSeconds(value)
        guard normalized != tonightOverrideBedSeconds else { return }
        tonightOverrideBedSeconds = normalized
        defaults.set(normalized, forKey: UserDefaultKeys.tonightOverrideBedTimeValue.rawValue)
        announceChange()
    }

    /// Keeps the adjustment until both its bedtime and its calendar day have passed, so an
    /// adjustment made after tonight's bedtime is not removed before it can be edited.
    func clearExpiredTonightOverride(at date: Date = Date(), calendar: Calendar = .autoupdatingCurrent) {
        guard let expiry = tonightOverrideExpiry(calendar: calendar), date >= expiry else { return }
        clearTonightOverrideSilently()
    }

    /// The latest of the adjustment's bedtime, the regular bedtime it replaces, and the end of its
    /// calendar day. An adjustment made after midnight belongs to the previous night, and moving its
    /// bedtime before now must not bring back the regular window it replaced.
    private func tonightOverrideExpiry(calendar: Calendar) -> Date? {
        guard let anchor = tonightOverrideCalendarDate?.date(calendar: calendar),
            let nextDay = calendar.date(byAdding: .day, value: 1, to: anchor)
        else {
            return nil
        }
        var expiry = max(tonightOverrideEnd(calendar: calendar) ?? anchor, calendar.startOfDay(for: nextDay))
        if let regular = weeklySchedule(oneNightOverride: nil).times(for: anchor, calendar: calendar),
            regular.bed != regular.start,
            let regularEnd = WallClockDateResolver.date(
                seconds: regular.bed,
                on: regular.bed < regular.start ? nextDay : anchor,
                calendar: calendar
            )
        {
            expiry = max(expiry, regularEnd)
        }
        return expiry
    }

    func tonightOverrideIsActive(
        at date: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        guard let tonightOverrideDate = tonightOverrideCalendarDate?.date(calendar: calendar),
            let end = tonightOverrideEnd(calendar: calendar)
        else {
            return false
        }
        return date >= tonightOverrideDate && date < end
    }

    /// Whether the adjustment belongs to today or to a night still in progress.
    func tonightOverridePending(
        at date: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        guard let expiry = tonightOverrideExpiry(calendar: calendar) else { return false }
        return date < expiry
    }

    /// The adjustment's bedtime, or nil when equal times make it an invalid window.
    private func tonightOverrideEnd(calendar: Calendar) -> Date? {
        guard let tonightOverrideDate = tonightOverrideCalendarDate?.date(calendar: calendar),
            tonightOverrideBedSeconds != tonightOverrideStartSeconds
        else {
            return nil
        }
        let crossesMidnight = tonightOverrideBedSeconds < tonightOverrideStartSeconds
        guard
            let endAnchor =
                crossesMidnight
                ? calendar.date(byAdding: .day, value: 1, to: tonightOverrideDate)
                : tonightOverrideDate
        else {
            return nil
        }
        return WallClockDateResolver.date(
            seconds: tonightOverrideBedSeconds,
            on: endAnchor,
            calendar: calendar
        )
    }

    func updateNotificationAlertsEnabled(_ value: Bool) {
        guard value != notificationAlertsEnabled else { return }
        notificationAlertsEnabled = value
        defaults.set(value, forKey: UserDefaultKeys.notificationAlertsEnabled.rawValue)
        announceChange()
    }

    func recordVisualNudge(at date: Date = Date()) {
        pendingVisualNudgeCount = Self.clampVisualNudgeCount(pendingVisualNudgeCount + 1)
        storeVisualNudge(at: date)
    }

    /// A preview shows the badge without adding to the count of real nudges.
    func recordVisualNudgePreview(at date: Date = Date()) {
        pendingVisualNudgeCount = max(pendingVisualNudgeCount, 1)
        storeVisualNudge(at: date)
    }

    private func storeVisualNudge(at date: Date) {
        lastVisualNudgeAt = date
        defaults.set(
            pendingVisualNudgeCount,
            forKey: UserDefaultKeys.pendingVisualNudgeCount.rawValue
        )
        defaults.set(date, forKey: UserDefaultKeys.lastVisualNudgeAt.rawValue)
    }

    func clearVisualNudges() {
        guard pendingVisualNudgeCount > 0 || lastVisualNudgeAt != nil else { return }
        pendingVisualNudgeCount = 0
        lastVisualNudgeAt = nil
        defaults.set(0, forKey: UserDefaultKeys.pendingVisualNudgeCount.rawValue)
        defaults.removeObject(forKey: UserDefaultKeys.lastVisualNudgeAt.rawValue)
    }

    func completeOnboarding() {
        guard !hasCompletedOnboarding else { return }
        hasCompletedOnboarding = true
        hasActivatedSchedule = true
        defaults.set(true, forKey: UserDefaultKeys.hasActivatedSchedule.rawValue)
        defaults.set(
            Self.currentOnboardingVersion,
            forKey: UserDefaultKeys.onboardingVersion.rawValue
        )
        announceChange()
    }

    func replayOnboarding() {
        // Posted on every request so Preferences can scroll back to a Welcome card that is already shown.
        NotificationCenter.default.post(name: .beddyWelcomeGuideRequested, object: self)
        guard hasCompletedOnboarding else { return }
        // Session only: persisting the replay would reopen Preferences at every launch until Start is pressed.
        hasCompletedOnboarding = false
        announceChange()
    }

    func restoreRecommendedDefaults(calendar: Calendar = .autoupdatingCurrent) {
        startSeconds = Self.defaultStartSeconds
        bedSeconds = Self.defaultBedSeconds
        snoozeMinutes = 30
        maximumPersonality = .zombie
        frequencyMinutes = Self.defaultFrequencyMinutes
        personality = .shy
        progressiveMode = false
        mutedUntil = nil
        mutedWholeWindow = false
        clearFinishedWindow()
        voiceVolume = Self.defaultVoiceVolume
        nudgeDelivery = .sound
        activeWeekdays = Set(1...7)
        alternateScheduleEnabled = false
        alternateScheduleWeekdays = [6, 7]
        alternateStartSeconds = Self.defaultStartSeconds
        alternateBedSeconds = Self.defaultBedSeconds
        primaryScheduleName = "Regular"
        alternateScheduleName = "Alternate"
        alternateSchedulePattern = .selectedWeekdays
        rotationAnchorCalendarDate = LocalCalendarDate(date: Date(), calendar: calendar)
        rotationPrimaryDays = 4
        rotationAlternateDays = 4
        tonightOverrideCalendarDate = nil
        tonightOverrideStartSeconds = Self.defaultStartSeconds
        tonightOverrideBedSeconds = Self.defaultBedSeconds
        notificationAlertsEnabled = false
        pendingVisualNudgeCount = 0
        lastVisualNudgeAt = nil

        defaults.removeObject(forKey: UserDefaultKeys.mutedUntil.rawValue)
        defaults.removeObject(forKey: UserDefaultKeys.lastVisualNudgeAt.rawValue)
        persistAll()
        announceChange()
    }

    func finishWindow(until date: Date) {
        finishedBadgeCount = pendingVisualNudgeCount
        finishedBadgeDate = lastVisualNudgeAt
        finishedWindowEnd = date
        pendingVisualNudgeCount = 0
        lastVisualNudgeAt = nil
        mutedUntil = date
        mutedWholeWindow = false
        defaults.set(date, forKey: UserDefaultKeys.mutedUntil.rawValue)
        defaults.set(true, forKey: UserDefaultKeys.isMuted.rawValue)
        persistAll()
        announceChange()
    }

    @discardableResult
    func undoFinishedWindow(at date: Date = Date()) -> Bool {
        guard let end = finishedWindowEnd, end == mutedUntil, date < end else { return false }
        pendingVisualNudgeCount = Self.clampVisualNudgeCount(pendingVisualNudgeCount + finishedBadgeCount)
        lastVisualNudgeAt = [lastVisualNudgeAt, finishedBadgeDate].compactMap { $0 }.max()
        persistAll()
        resumeNudges()
        return true
    }

    private func clearFinishedWindow() {
        finishedWindowEnd = nil
        finishedBadgeCount = 0
        finishedBadgeDate = nil
        for key in [UserDefaultKeys.finishedWindowEnd, .finishedBadgeCount, .finishedBadgeDate] {
            defaults.removeObject(forKey: key.rawValue)
        }
    }

    /// Mutes until `date`. `wholeWindow` marks a pause that lasts until bedtime, which then
    /// follows the bedtime if the window is later widened.
    func mute(until date: Date, wholeWindow: Bool = false) {
        clearFinishedWindow()
        mutedUntil = date
        mutedWholeWindow = wholeWindow
        defaults.set(date, forKey: UserDefaultKeys.mutedUntil.rawValue)
        defaults.set(true, forKey: UserDefaultKeys.isMuted.rawValue)
        defaults.set(wholeWindow, forKey: UserDefaultKeys.mutedWholeWindow.rawValue)
        announceChange()
    }

    /// Whether the current mute is a whole-window pause or an "I'm heading to bed" finish.
    var mutesWholeWindow: Bool {
        guard let mutedUntil else { return false }
        return mutedWholeWindow || finishedWindowEnd == mutedUntil
    }

    /// Moves a whole-window mute to a later bedtime. Silent, for use mid-recalculation.
    func extendWholeWindowMute(until date: Date) {
        guard mutesWholeWindow, let mutedUntil, date > mutedUntil else { return }
        if finishedWindowEnd == mutedUntil {
            finishedWindowEnd = date
        }
        self.mutedUntil = date
        persistAll()
    }

    func resumeNudges() {
        guard mutedUntil != nil || defaults.bool(forKey: UserDefaultKeys.isMuted.rawValue) else { return }
        mutedUntil = nil
        mutedWholeWindow = false
        clearFinishedWindow()
        defaults.removeObject(forKey: UserDefaultKeys.mutedUntil.rawValue)
        defaults.set(false, forKey: UserDefaultKeys.isMuted.rawValue)
        defaults.set(false, forKey: UserDefaultKeys.mutedWholeWindow.rawValue)
        announceChange()
    }

    func isMuted(at date: Date = Date()) -> Bool {
        guard let mutedUntil else { return false }
        return date < mutedUntil
    }

    func clearExpiredMute(at date: Date = Date()) {
        guard let mutedUntil, mutedUntil <= date else { return }
        self.mutedUntil = nil
        mutedWholeWindow = false
        clearFinishedWindow()
        defaults.removeObject(forKey: UserDefaultKeys.mutedUntil.rawValue)
        defaults.set(false, forKey: UserDefaultKeys.isMuted.rawValue)
        defaults.set(false, forKey: UserDefaultKeys.mutedWholeWindow.rawValue)
    }

    private func persistAll() {
        defaults.set(finishedWindowEnd, forKey: UserDefaultKeys.finishedWindowEnd.rawValue)
        defaults.set(finishedBadgeCount, forKey: UserDefaultKeys.finishedBadgeCount.rawValue)
        defaults.set(finishedBadgeDate, forKey: UserDefaultKeys.finishedBadgeDate.rawValue)
        defaults.set(snoozeMinutes, forKey: UserDefaultKeys.snoozeMinutes.rawValue)
        defaults.set(maximumPersonality.rawValue, forKey: UserDefaultKeys.maximumPersonality.rawValue)
        defaults.set(Double(startSeconds), forKey: UserDefaultKeys.startTimeValue.rawValue)
        defaults.set(Double(bedSeconds), forKey: UserDefaultKeys.bedTimeValue.rawValue)
        defaults.set(frequencyMinutes, forKey: UserDefaultKeys.frequency.rawValue)
        defaults.set(personality.rawValue, forKey: UserDefaultKeys.selectedSound.rawValue)
        defaults.set(progressiveMode, forKey: UserDefaultKeys.progressive.rawValue)
        defaults.set(voiceVolume, forKey: UserDefaultKeys.voiceVolume.rawValue)
        defaults.set(nudgeDelivery.rawValue, forKey: UserDefaultKeys.nudgeDelivery.rawValue)
        defaults.set(activeWeekdays.sorted(), forKey: UserDefaultKeys.activeWeekdays.rawValue)
        defaults.set(alternateScheduleEnabled, forKey: UserDefaultKeys.alternateScheduleEnabled.rawValue)
        defaults.set(
            alternateScheduleWeekdays.sorted(),
            forKey: UserDefaultKeys.alternateScheduleWeekdays.rawValue
        )
        defaults.set(Double(alternateStartSeconds), forKey: UserDefaultKeys.alternateStartTimeValue.rawValue)
        defaults.set(Double(alternateBedSeconds), forKey: UserDefaultKeys.alternateBedTimeValue.rawValue)
        defaults.set(primaryScheduleName, forKey: UserDefaultKeys.primaryScheduleName.rawValue)
        defaults.set(alternateScheduleName, forKey: UserDefaultKeys.alternateScheduleName.rawValue)
        defaults.set(
            alternateSchedulePattern.rawValue,
            forKey: UserDefaultKeys.alternateSchedulePattern.rawValue
        )
        defaults.set(
            rotationAnchorCalendarDate.storedValue,
            forKey: UserDefaultKeys.rotationAnchorDate.rawValue
        )
        defaults.set(rotationPrimaryDays, forKey: UserDefaultKeys.rotationPrimaryDays.rawValue)
        defaults.set(rotationAlternateDays, forKey: UserDefaultKeys.rotationAlternateDays.rawValue)
        defaults.set(
            Double(tonightOverrideStartSeconds),
            forKey: UserDefaultKeys.tonightOverrideStartTimeValue.rawValue
        )
        defaults.set(
            Double(tonightOverrideBedSeconds),
            forKey: UserDefaultKeys.tonightOverrideBedTimeValue.rawValue
        )
        if let tonightOverrideCalendarDate {
            defaults.set(
                tonightOverrideCalendarDate.storedValue,
                forKey: UserDefaultKeys.tonightOverrideDate.rawValue
            )
        } else {
            defaults.removeObject(forKey: UserDefaultKeys.tonightOverrideDate.rawValue)
        }
        defaults.removeObject(forKey: UserDefaultKeys.separateWeekendSchedule.rawValue)
        defaults.removeObject(forKey: UserDefaultKeys.weekendStartTimeValue.rawValue)
        defaults.removeObject(forKey: UserDefaultKeys.weekendBedTimeValue.rawValue)
        defaults.set(
            notificationAlertsEnabled,
            forKey: UserDefaultKeys.notificationAlertsEnabled.rawValue
        )
        defaults.set(
            pendingVisualNudgeCount,
            forKey: UserDefaultKeys.pendingVisualNudgeCount.rawValue
        )
        if let lastVisualNudgeAt {
            defaults.set(lastVisualNudgeAt, forKey: UserDefaultKeys.lastVisualNudgeAt.rawValue)
        } else {
            defaults.removeObject(forKey: UserDefaultKeys.lastVisualNudgeAt.rawValue)
        }

        if hasCompletedOnboarding {
            defaults.set(
                Self.currentOnboardingVersion,
                forKey: UserDefaultKeys.onboardingVersion.rawValue
            )
        }

        if let mutedUntil {
            defaults.set(mutedUntil, forKey: UserDefaultKeys.mutedUntil.rawValue)
            defaults.set(true, forKey: UserDefaultKeys.isMuted.rawValue)
        } else {
            defaults.set(false, forKey: UserDefaultKeys.isMuted.rawValue)
        }
        defaults.set(mutedWholeWindow, forKey: UserDefaultKeys.mutedWholeWindow.rawValue)
    }

    private func announceChange() {
        NotificationCenter.default.post(name: .beddySettingsDidChange, object: self)
    }

    private static func readSeconds(
        key: UserDefaultKeys,
        from defaults: UserDefaults,
        fallback: Int
    ) -> Int {
        let stored = defaults.object(forKey: key.rawValue) as? NSNumber
        return clampSeconds(stored?.intValue ?? fallback)
    }

    private static func readMigratedSeconds(
        key: UserDefaultKeys,
        legacyKey: UserDefaultKeys,
        from defaults: UserDefaults,
        fallback: Int
    ) -> Int {
        let stored =
            defaults.object(forKey: key.rawValue) as? NSNumber
            ?? defaults.object(forKey: legacyKey.rawValue) as? NSNumber
        return clampSeconds(stored?.intValue ?? fallback)
    }

    private static func readMigratedBool(
        key: UserDefaultKeys,
        legacyKey: UserDefaultKeys,
        from defaults: UserDefaults,
        fallback: Bool
    ) -> Bool {
        if let stored = storedBool(defaults.object(forKey: key.rawValue)) {
            return stored
        }
        return storedBool(defaults.object(forKey: legacyKey.rawValue)) ?? fallback
    }

    private static func storedBool(_ object: Any?) -> Bool? {
        if let value = object as? Bool {
            return value
        }
        if let value = object as? NSNumber {
            return value.boolValue
        }
        if let value = object as? String {
            switch value.lowercased() {
            case "1", "true", "yes": return true
            case "0", "false", "no": return false
            default: return nil
            }
        }
        return nil
    }

    private static func clampSeconds(_ value: Int) -> Int {
        min(max(value, 0), secondsPerDay - 1)
    }

    private static func clampFrequency(_ value: Double) -> Double {
        guard value.isFinite else { return defaultFrequencyMinutes }
        return min(max(value, 1), 30)
    }

    private static func clampVolume(_ value: Double) -> Double {
        guard value.isFinite else { return defaultVoiceVolume }
        return min(max(value, 0), 1)
    }

    private static func clampVisualNudgeCount(_ value: Int) -> Int {
        min(max(value, 0), 99)
    }

    private static func clampCycleDays(_ value: Int) -> Int {
        min(max(value, 1), 28)
    }

    private static func readScheduleName(_ value: String?, fallback: String) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return String((trimmed.isEmpty ? fallback : trimmed).prefix(30))
    }

    private static func readCalendarDate(
        key: UserDefaultKeys,
        from defaults: UserDefaults,
        fallback: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> LocalCalendarDate {
        if let stored = defaults.string(forKey: key.rawValue),
            let calendarDate = LocalCalendarDate(storedValue: stored)
        {
            return calendarDate
        }
        if let legacyDate = defaults.object(forKey: key.rawValue) as? Date {
            return LocalCalendarDate(date: legacyDate, calendar: calendar)
        }
        return LocalCalendarDate(date: fallback, calendar: calendar)
    }

    private static func readOptionalCalendarDate(
        key: UserDefaultKeys,
        from defaults: UserDefaults,
        calendar: Calendar = .autoupdatingCurrent
    ) -> LocalCalendarDate? {
        if let stored = defaults.string(forKey: key.rawValue) {
            return LocalCalendarDate(storedValue: stored)
        }
        return (defaults.object(forKey: key.rawValue) as? Date).map {
            LocalCalendarDate(date: $0, calendar: calendar)
        }
    }

    private static func readActiveWeekdays(from defaults: UserDefaults) -> Set<Int> {
        guard let stored = defaults.array(forKey: UserDefaultKeys.activeWeekdays.rawValue) as? [Int] else {
            return Set(1...7)
        }
        return Set(stored.filter { (1...7).contains($0) })
    }

    private static func readAlternateScheduleWeekdays(from defaults: UserDefaults) -> Set<Int> {
        guard
            let stored = defaults.array(forKey: UserDefaultKeys.alternateScheduleWeekdays.rawValue)
                as? [Int]
        else {
            // Preserve the original Friday and Saturday behavior for upgraded users.
            return [6, 7]
        }
        return Set(stored.filter { (1...7).contains($0) })
    }

    private static func hasExistingConfiguration(in defaults: UserDefaults) -> Bool {
        let configurationKeys: [UserDefaultKeys] = [
            .bedTimeValue,
            .startTimeValue,
            .runStartup,
            .selectedSound,
            .frequency,
            .progressive,
        ]
        return configurationKeys.contains { defaults.object(forKey: $0.rawValue) != nil }
    }
}
