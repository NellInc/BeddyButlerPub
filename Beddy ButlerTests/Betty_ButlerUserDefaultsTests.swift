import Foundation
import XCTest

@testable import Beddy_Butler

final class BeddyButlerUserDefaultsTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let suiteName = "BeddyButlerTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create isolated user defaults")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @MainActor
    func testDefaultsUseSensibleFirstLaunchValues() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.startSeconds, 21 * 3_600 + 30 * 60)
        XCTAssertEqual(settings.bedSeconds, 23 * 3_600)
        XCTAssertEqual(settings.frequencyMinutes, 8)
        XCTAssertEqual(settings.personality, .shy)
        XCTAssertFalse(settings.progressiveMode)
        XCTAssertEqual(settings.voiceVolume, 0.8)
        XCTAssertEqual(settings.nudgeDelivery, .sound)
        XCTAssertEqual(settings.activeWeekdays, Set(1...7))
        XCTAssertFalse(settings.alternateScheduleEnabled)
        XCTAssertEqual(settings.alternateScheduleWeekdays, [6, 7])
        XCTAssertEqual(settings.primaryScheduleName, "Regular")
        XCTAssertEqual(settings.alternateScheduleName, "Alternate")
        XCTAssertEqual(settings.alternateSchedulePattern, .selectedWeekdays)
        XCTAssertEqual(settings.rotationPrimaryDays, 4)
        XCTAssertEqual(settings.rotationAlternateDays, 4)
        XCTAssertNil(settings.tonightOverrideDate)
        XCTAssertFalse(settings.notificationAlertsEnabled)
        XCTAssertEqual(settings.pendingVisualNudgeCount, 0)
        XCTAssertNil(settings.lastVisualNudgeAt)
        XCTAssertFalse(settings.hasCompletedOnboarding)
        XCTAssertFalse(AppSettings(defaults: defaults).hasCompletedOnboarding)
    }

    @MainActor
    func testLegacyNumbersAndPersonalityAreMigrated() {
        let defaults = freshDefaults()
        defaults.set(75_000.0, forKey: UserDefaultKeys.startTimeValue.rawValue)
        defaults.set(85_000, forKey: UserDefaultKeys.bedTimeValue.rawValue)
        defaults.set("INSISTENT", forKey: UserDefaultKeys.selectedSound.rawValue)
        defaults.set(14, forKey: UserDefaultKeys.frequency.rawValue)

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.startSeconds, 75_000)
        XCTAssertEqual(settings.bedSeconds, 85_000)
        XCTAssertEqual(settings.personality, .insistent)
        XCTAssertEqual(settings.frequencyMinutes, 14)
        XCTAssertTrue(settings.hasCompletedOnboarding)
    }

    @MainActor
    func testUpdatesPersistAndClampUnsafeValues() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults)

        settings.updateStartSeconds(-10)
        settings.updateBedSeconds(100_000)
        settings.updateFrequencyMinutes(100)
        settings.updatePersonality(.zombie)
        settings.updateProgressiveMode(true)
        settings.updateVoiceVolume(2)
        settings.updateNudgeDelivery(.visual)
        settings.updateActiveWeekday(2, isActive: false)
        settings.updateAlternateScheduleEnabled(true)
        settings.updateAlternateScheduleWeekday(6, isSelected: false)
        settings.updateAlternateScheduleWeekday(1, isSelected: true)
        settings.updateAlternateStartSeconds(22 * 3_600)
        settings.updateAlternateBedSeconds(2 * 3_600)
        settings.updatePrimaryScheduleName("Weekday")
        settings.updateAlternateScheduleName("Night shift")
        settings.updateAlternateSchedulePattern(.rotatingCycle)
        settings.updateRotationPrimaryDays(35)
        settings.updateRotationAlternateDays(0)
        let tonight = Date(timeIntervalSince1970: 2_000_000_000)
        settings.enableTonightOverride(on: tonight)
        settings.updateTonightOverrideStartSeconds(20 * 3_600)
        settings.updateTonightOverrideBedSeconds(1 * 3_600)
        settings.updateNotificationAlertsEnabled(true)
        settings.completeOnboarding()

        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.startSeconds, 0)
        XCTAssertEqual(restored.bedSeconds, 86_399)
        XCTAssertEqual(restored.frequencyMinutes, 30)
        XCTAssertEqual(restored.personality, .zombie)
        XCTAssertTrue(restored.progressiveMode)
        XCTAssertEqual(restored.voiceVolume, 1)
        XCTAssertEqual(restored.nudgeDelivery, .visual)
        XCTAssertFalse(restored.activeWeekdays.contains(2))
        XCTAssertTrue(restored.alternateScheduleEnabled)
        XCTAssertEqual(restored.alternateScheduleWeekdays, [1, 7])
        XCTAssertEqual(restored.alternateStartSeconds, 22 * 3_600)
        XCTAssertEqual(restored.alternateBedSeconds, 2 * 3_600)
        XCTAssertEqual(restored.primaryScheduleName, "Weekday")
        XCTAssertEqual(restored.alternateScheduleName, "Night shift")
        XCTAssertEqual(restored.alternateSchedulePattern, .rotatingCycle)
        XCTAssertEqual(restored.rotationPrimaryDays, 28)
        XCTAssertEqual(restored.rotationAlternateDays, 1)
        XCTAssertEqual(
            restored.tonightOverrideDate,
            Calendar.autoupdatingCurrent.startOfDay(for: tonight)
        )
        XCTAssertEqual(restored.tonightOverrideStartSeconds, 20 * 3_600)
        XCTAssertEqual(restored.tonightOverrideBedSeconds, 1 * 3_600)
        XCTAssertTrue(restored.notificationAlertsEnabled)
        XCTAssertTrue(restored.hasCompletedOnboarding)
    }

    @MainActor
    func testLegacyWeekendScheduleMigratesToFridayAndSaturdayAlternateNights() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: UserDefaultKeys.separateWeekendSchedule.rawValue)
        defaults.set(23 * 3_600, forKey: UserDefaultKeys.weekendStartTimeValue.rawValue)
        defaults.set(2 * 3_600, forKey: UserDefaultKeys.weekendBedTimeValue.rawValue)

        let settings = AppSettings(defaults: defaults)

        XCTAssertTrue(settings.alternateScheduleEnabled)
        XCTAssertEqual(settings.alternateScheduleWeekdays, [6, 7])
        XCTAssertEqual(settings.alternateStartSeconds, 23 * 3_600)
        XCTAssertEqual(settings.alternateBedSeconds, 2 * 3_600)
        XCTAssertNil(defaults.object(forKey: UserDefaultKeys.separateWeekendSchedule.rawValue))
        XCTAssertEqual(
            defaults.array(forKey: UserDefaultKeys.alternateScheduleWeekdays.rawValue) as? [Int],
            [6, 7]
        )
    }

    @MainActor
    func testAlternateScheduleAcceptsCommandLineStyleBooleanStrings() {
        let defaults = freshDefaults()
        defaults.set("YES", forKey: UserDefaultKeys.alternateScheduleEnabled.rawValue)

        XCTAssertTrue(AppSettings(defaults: defaults).alternateScheduleEnabled)
    }

    @MainActor
    func testVolumeClampsAtBothEnds() {
        let settings = AppSettings(defaults: freshDefaults())

        settings.updateVoiceVolume(-1)
        XCTAssertEqual(settings.voiceVolume, 0)
        settings.updateVoiceVolume(0.55)
        XCTAssertEqual(settings.voiceVolume, 0.55)
        settings.updateVoiceVolume(20)
        XCTAssertEqual(settings.voiceVolume, 1)
    }

    @MainActor
    func testNonFiniteFrequencyAndVolumeRecoverToSafeDefaults() {
        let defaults = freshDefaults()
        defaults.set(Double.nan, forKey: UserDefaultKeys.frequency.rawValue)
        defaults.set(Double.infinity, forKey: UserDefaultKeys.voiceVolume.rawValue)

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.frequencyMinutes, AppSettings.defaultFrequencyMinutes)
        XCTAssertEqual(settings.voiceVolume, AppSettings.defaultVoiceVolume)
        XCTAssertTrue(settings.frequencyMinutes.isFinite)
        XCTAssertTrue(settings.voiceVolume.isFinite)

        settings.updateFrequencyMinutes(-Double.infinity)
        settings.updateVoiceVolume(Double.nan)
        XCTAssertEqual(settings.frequencyMinutes, AppSettings.defaultFrequencyMinutes)
        XCTAssertEqual(settings.voiceVolume, AppSettings.defaultVoiceVolume)
    }

    func testCalendarDateIdentitySurvivesTimeZoneChanges() throws {
        var london = Calendar(identifier: .gregorian)
        london.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let selectedDate = try XCTUnwrap(
            london.date(from: DateComponents(year: 2026, month: 7, day: 21))
        )

        let calendarDate = LocalCalendarDate(date: selectedDate, calendar: london)
        let reconstructed = try XCTUnwrap(calendarDate.date(calendar: newYork))

        XCTAssertEqual(calendarDate.storedValue, "2026-07-21")
        XCTAssertEqual(
            newYork.dateComponents([.year, .month, .day], from: reconstructed),
            DateComponents(year: 2026, month: 7, day: 21)
        )
    }

    @MainActor
    func testUnknownNudgeDeliveryMigratesToSound() {
        let defaults = freshDefaults()
        defaults.set("Haptic", forKey: UserDefaultKeys.nudgeDelivery.rawValue)

        XCTAssertEqual(AppSettings(defaults: defaults).nudgeDelivery, .sound)
    }

    @MainActor
    func testVisualNudgeStatePersistsUntilAcknowledged() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults)
        let timestamp = Date(timeIntervalSince1970: 2_000_000_000)

        settings.recordVisualNudge(at: timestamp)
        settings.recordVisualNudge(at: timestamp.addingTimeInterval(60))

        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.pendingVisualNudgeCount, 2)
        XCTAssertEqual(restored.lastVisualNudgeAt, timestamp.addingTimeInterval(60))

        restored.clearVisualNudges()
        let cleared = AppSettings(defaults: defaults)
        XCTAssertEqual(cleared.pendingVisualNudgeCount, 0)
        XCTAssertNil(cleared.lastVisualNudgeAt)
    }

    @MainActor
    func testLegacyDisplayValuesNormalizeToStableIdentifiers() {
        let defaults = freshDefaults()
        defaults.set("Visual", forKey: UserDefaultKeys.nudgeDelivery.rawValue)
        defaults.set("Zombie", forKey: UserDefaultKeys.selectedSound.rawValue)

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.nudgeDelivery, .visual)
        XCTAssertEqual(settings.personality, .zombie)
        XCTAssertEqual(defaults.string(forKey: UserDefaultKeys.nudgeDelivery.rawValue), "visual")
        XCTAssertEqual(defaults.string(forKey: UserDefaultKeys.selectedSound.rawValue), "zombie")
    }

    @MainActor
    func testMuteExpiresAndCanBeResumed() {
        let settings = AppSettings(defaults: freshDefaults())
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        settings.mute(until: now.addingTimeInterval(600))
        XCTAssertTrue(settings.isMuted(at: now))
        settings.clearExpiredMute(at: now.addingTimeInterval(601))
        XCTAssertFalse(settings.isMuted(at: now.addingTimeInterval(601)))

        settings.mute(until: now.addingTimeInterval(600))
        settings.resumeNudges()
        XCTAssertFalse(settings.isMuted(at: now))
    }

    @MainActor
    func testOneNightOverrideExpiresAfterItsCrossMidnightWindow() throws {
        let settings = AppSettings(defaults: freshDefaults())
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        let anchor = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 21))
        )
        settings.enableTonightOverride(on: anchor, calendar: calendar)
        settings.updateTonightOverrideStartSeconds(22 * 3_600)
        settings.updateTonightOverrideBedSeconds(1 * 3_600)

        let beforeBed = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 0, minute: 30))
        )
        settings.clearExpiredTonightOverride(at: beforeBed, calendar: calendar)
        XCTAssertNotNil(settings.tonightOverrideDate)

        let afterBed = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 1, minute: 1))
        )
        settings.clearExpiredTonightOverride(at: afterBed, calendar: calendar)
        XCTAssertNil(settings.tonightOverrideDate)
    }

    @MainActor
    func testWelcomeGuideCanBeReplayedWithoutChangingProductSettings() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.updatePersonality(.zombie)
        settings.updateFrequencyMinutes(19)
        settings.completeOnboarding()

        settings.replayOnboarding()

        XCTAssertFalse(settings.hasCompletedOnboarding)
        XCTAssertEqual(settings.personality, .zombie)
        XCTAssertEqual(settings.frequencyMinutes, 19)
        XCTAssertFalse(AppSettings(defaults: defaults).hasCompletedOnboarding)
    }

    @MainActor
    func testRestoreRecommendedDefaultsResetsProductStateAndKeepsOnboardingComplete() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.updateStartSeconds(1)
        settings.updateBedSeconds(2)
        settings.updateFrequencyMinutes(23)
        settings.updatePersonality(.zombie)
        settings.updateProgressiveMode(true)
        settings.updateVoiceVolume(0.2)
        settings.updateNudgeDelivery(.both)
        settings.updateActiveWeekday(2, isActive: false)
        settings.updateAlternateScheduleEnabled(true)
        settings.updateAlternateScheduleWeekday(1, isSelected: true)
        settings.updateAlternateStartSeconds(20 * 3_600)
        settings.updateAlternateBedSeconds(3 * 3_600)
        settings.updatePrimaryScheduleName("Changed")
        settings.updateAlternateScheduleName("Changed too")
        settings.updateAlternateSchedulePattern(.rotatingCycle)
        settings.updateRotationPrimaryDays(8)
        settings.updateRotationAlternateDays(9)
        settings.enableTonightOverride()
        settings.updateNotificationAlertsEnabled(true)
        settings.recordVisualNudge()
        settings.mute(until: Date().addingTimeInterval(3_600))
        settings.completeOnboarding()

        settings.restoreRecommendedDefaults()

        XCTAssertEqual(settings.startSeconds, AppSettings.defaultStartSeconds)
        XCTAssertEqual(settings.bedSeconds, AppSettings.defaultBedSeconds)
        XCTAssertEqual(settings.frequencyMinutes, AppSettings.defaultFrequencyMinutes)
        XCTAssertEqual(settings.personality, .shy)
        XCTAssertFalse(settings.progressiveMode)
        XCTAssertEqual(settings.voiceVolume, AppSettings.defaultVoiceVolume)
        XCTAssertEqual(settings.nudgeDelivery, .sound)
        XCTAssertEqual(settings.activeWeekdays, Set(1...7))
        XCTAssertFalse(settings.alternateScheduleEnabled)
        XCTAssertEqual(settings.alternateScheduleWeekdays, [6, 7])
        XCTAssertEqual(settings.alternateStartSeconds, AppSettings.defaultStartSeconds)
        XCTAssertEqual(settings.alternateBedSeconds, AppSettings.defaultBedSeconds)
        XCTAssertEqual(settings.primaryScheduleName, "Regular")
        XCTAssertEqual(settings.alternateScheduleName, "Alternate")
        XCTAssertEqual(settings.alternateSchedulePattern, .selectedWeekdays)
        XCTAssertEqual(settings.rotationPrimaryDays, 4)
        XCTAssertEqual(settings.rotationAlternateDays, 4)
        XCTAssertNil(settings.tonightOverrideDate)
        XCTAssertFalse(settings.notificationAlertsEnabled)
        XCTAssertEqual(settings.pendingVisualNudgeCount, 0)
        XCTAssertNil(settings.lastVisualNudgeAt)
        XCTAssertNil(settings.mutedUntil)
        XCTAssertTrue(settings.hasCompletedOnboarding)

        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.personality, .shy)
        XCTAssertEqual(restored.activeWeekdays, Set(1...7))
        XCTAssertNil(restored.mutedUntil)
        XCTAssertTrue(restored.hasCompletedOnboarding)
    }
}
