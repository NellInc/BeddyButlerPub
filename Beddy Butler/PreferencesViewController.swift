import AppKit
import SwiftUI

struct WallClockTime {
    static func date(
        for seconds: Int,
        relativeTo referenceDate: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date {
        WallClockDateResolver.date(
            seconds: seconds,
            on: referenceDate,
            calendar: calendar
        ) ?? referenceDate
    }

    static func seconds(from date: Date, calendar: Calendar = .autoupdatingCurrent) -> Int {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        return (components.hour ?? 0) * 3_600
            + (components.minute ?? 0) * 60
            + (components.second ?? 0)
    }
}

enum LocalizedScheduleText {
    static func time(
        _ date: Date,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct WeekdayChoice: Identifiable {
    let weekday: Int
    let label: String
    let fullLabel: String

    var id: Int { weekday }
}

@MainActor
final class PreferencesWindowController: NSWindowController {
    init(
        settings: AppSettings,
        scheduler: ButlerTimer,
        loginItemManager: LoginItemManager,
        notificationManager: LocalNotificationManager
    ) {
        let content = PreferencesView(
            settings: settings,
            scheduler: scheduler,
            loginItemManager: loginItemManager,
            notificationManager: notificationManager
        )
        let environment = ProcessInfo.processInfo.environment
        let hostingController = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Beddy Butler Preferences"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        if environment["BEDDY_BUTLER_APPEARANCE"] == "light" {
            window.appearance = NSAppearance(named: .aqua)
        } else {
            window.appearance = NSAppearance(named: .darkAqua)
        }
        window.setContentSize(NSSize(width: 720, height: 800))
        window.minSize = NSSize(width: 640, height: 680)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.center()

        super.init(window: window)
        shouldCascadeWindows = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func present() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }
}

private struct AnimatedButlerArtwork: View {
    enum Presentation {
        case header
        case preview
    }

    let personality: ButlerPersonality
    let presentation: Presentation
    let viewportHeight: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isWithinViewport = true

    var body: some View {
        artwork
            .shadow(color: accent.opacity(0.18), radius: 9, x: 0, y: 5)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.24),
                value: personality
            )
            .background {
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .named("beddy-preferences-scroll"))
                    Color.clear
                        .onAppear {
                            updateVisibility(frame)
                        }
                        .onChange(of: frame) { updatedFrame in
                            updateVisibility(updatedFrame)
                        }
                }
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var artwork: some View {
        switch presentation {
        case .header:
            Image(personality.assetName)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: 108, height: 96, alignment: .top)
                .scaleEffect(1.42, anchor: .top)
                .frame(width: 108, height: 96, alignment: .top)
                .clipped()
                .drawingGroup(opaque: false, colorMode: .linear)
        case .preview:
            ButlerRiggedView(
                personality: personality,
                motionEnabled: !reduceMotion && isWithinViewport,
                isVisible: isWithinViewport,
                contentMode: .fit,
                intensity: 1
            )
            .frame(width: 144, height: 172)
        }
    }

    private func updateVisibility(_ frame: CGRect) {
        guard viewportHeight > 0 else { return }
        let isVisible = frame.maxY > -16 && frame.minY < viewportHeight + 16
        if isVisible != isWithinViewport {
            isWithinViewport = isVisible
        }
    }

    private var accent: Color {
        switch personality {
        case .shy: BeddyPalette.blue
        case .insistent: BeddyPalette.warm
        case .zombie: BeddyPalette.zombie
        }
    }
}

private struct ScheduleNameTextField: View {
    let placeholder: String
    let value: String
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let commit: (String) -> String

    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(
        placeholder: String,
        value: String,
        accessibilityLabel: String,
        accessibilityIdentifier: String,
        commit: @escaping (String) -> String
    ) {
        self.placeholder = placeholder
        self.value = value
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityIdentifier = accessibilityIdentifier
        self.commit = commit
        _draft = State(initialValue: value)
    }

    var body: some View {
        TextField(placeholder, text: $draft)
            .textFieldStyle(.roundedBorder)
            .focused($isFocused)
            .onSubmit(commitDraft)
            .onChange(of: isFocused) { focused in
                if !focused {
                    commitDraft()
                }
            }
            .onChange(of: value) { updatedValue in
                if !isFocused {
                    draft = updatedValue
                }
            }
            .accessibilityLabel(accessibilityLabel)
            .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func commitDraft() {
        draft = commit(draft)
    }
}

struct PreferencesView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var scheduler: ButlerTimer
    @ObservedObject var loginItemManager: LoginItemManager
    @ObservedObject var notificationManager: LocalNotificationManager
    let captureAllSections: Bool

    @State private var timeZoneIdentifier = TimeZone.autoupdatingCurrent.identifier
    @State private var scrollViewportHeight: CGFloat = 800
    @State private var showingRestoreDefaultsConfirmation = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        settings: AppSettings,
        scheduler: ButlerTimer,
        loginItemManager: LoginItemManager,
        notificationManager: LocalNotificationManager,
        captureAllSections: Bool = false
    ) {
        self.settings = settings
        self.scheduler = scheduler
        self.loginItemManager = loginItemManager
        self.notificationManager = notificationManager
        self.captureAllSections = captureAllSections
    }

    @ViewBuilder
    var body: some View {
        if captureAllSections {
            ZStack {
                BeddyBackdrop()
                preferenceSections
                    .coordinateSpace(name: "beddy-preferences-scroll")
            }
            .frame(width: 720)
            .tint(BeddyPalette.blue)
            .preferredColorScheme(.dark)
        } else {
            ZStack {
                BeddyBackdrop()

                ScrollViewReader { proxy in
                    ScrollView {
                        preferenceSections
                    }
                    .coordinateSpace(name: "beddy-preferences-scroll")
                    .background {
                        GeometryReader { viewport in
                            Color.clear
                                .onAppear {
                                    scrollViewportHeight = viewport.size.height
                                }
                                .onChange(of: viewport.size.height) { updatedHeight in
                                    scrollViewportHeight = updatedHeight
                                }
                        }
                    }
                    .onChange(of: settings.hasCompletedOnboarding) { completed in
                        if completed {
                            DispatchQueue.main.async {
                                proxy.scrollTo("preferences-top", anchor: .top)
                            }
                        }
                    }
                }
            }
            .frame(minWidth: 640, minHeight: 680)
            .tint(BeddyPalette.blue)
            .preferredColorScheme(.dark)
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                timeZoneIdentifier = TimeZone.autoupdatingCurrent.identifier
            }
        }
    }

    private var preferenceSections: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if !settings.hasCompletedOnboarding {
                welcomeSection
            }
            tonightSection
            scheduleSection
            personalitySection
            if settings.nudgeDelivery.includesSound {
                behaviorSection
            }
            startupSection
            footer
        }
        .padding(.horizontal, 26)
        .padding(.top, 18)
        .padding(.bottom, 24)
        .id("preferences-top")
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.2),
            value: settings.alternateScheduleEnabled
        )
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.2),
            value: settings.nudgeDelivery
        )
    }

    private var header: some View {
        HStack(spacing: 17) {
            AnimatedButlerArtwork(
                personality: .shy,
                presentation: .header,
                viewportHeight: scrollViewportHeight
            )

            VStack(alignment: .leading, spacing: 3) {
                Text("YOUR EVENING, BEAUTIFULLY")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(BeddyPalette.blueBright)
                Text("Beddy Butler")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(BeddyPalette.ink)
                Text("Gentle reminders for a better-rested tomorrow.")
                    .foregroundStyle(BeddyPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Label(headerStatusTitle, systemImage: headerStatusSymbol)
                .font(.callout.weight(.semibold))
                .foregroundStyle(headerStatusTint)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .glassCapsule(tint: headerStatusTint)
                .accessibilityLabel("Beddy Butler status: \(headerStatusTitle)")
        }
        .padding(.horizontal, 2)
        .padding(.top, 4)
    }

    private var welcomeSection: some View {
        BeddyCard(
            title: "Welcome to the night shift",
            symbol: "sparkles",
            tint: BeddyPalette.violet,
            emphasized: true
        ) {
            Text("Set tonight's routine below. Beddy Butler saves changes instantly and waits in your menu bar.")
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 7) {
                Label("Choose when reminders begin and when you intend to be in bed.", systemImage: "1.circle.fill")
                Label("Choose sound, a visual badge, or both; then preview it.", systemImage: "2.circle.fill")
                Label("Click Start Beddy Butler when tonight looks right.", systemImage: "3.circle.fill")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Button("Start Beddy Butler") {
                settings.completeOnboarding()
                scheduler.recalculate()
            }
            .primaryGlassButton()
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel("Start Beddy Butler")
            .accessibilityIdentifier("onboarding.start")
            .accessibilityHint("Completes setup; settings can still be changed at any time")
        }
    }

    private var tonightSection: some View {
        BeddyCard(
            title: "Tonight",
            symbol: settings.isMuted() ? "pause.circle.fill" : "moon.stars.fill",
            tint: settings.isMuted() ? BeddyPalette.warm : BeddyPalette.violet,
            emphasized: true
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: settings.isMuted() ? "pause.circle.fill" : "moon.stars.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(settings.isMuted() ? BeddyPalette.warm : BeddyPalette.violet)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(scheduleHeading)
                            .font(.title3.weight(.semibold))
                            .textSelection(.enabled)
                        Text(scheduleDetail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 10) {
                    if scheduler.visualNudgePending {
                        Button {
                            scheduler.acknowledgeVisualNudge()
                        } label: {
                            Label("Acknowledge Badge", systemImage: "checkmark")
                        }
                        .primaryGlassButton()
                        .accessibilityLabel("Acknowledge visual badge")
                        .accessibilityIdentifier("tonight.acknowledge")
                        .accessibilityHint("Clears the persistent visual bedtime nudge")
                    }

                    if settings.isMuted() {
                        Button {
                            scheduler.resumeNudges()
                        } label: {
                            Label("Resume Nudges", systemImage: "play.fill")
                        }
                        .primaryGlassButton()
                        .accessibilityLabel("Resume nudges")
                        .accessibilityIdentifier("tonight.resume")
                    } else {
                        Button {
                            scheduler.snooze()
                        } label: {
                            Label("Snooze 30 Minutes", systemImage: "timer")
                        }
                        .disabled(!scheduler.canSnooze)
                        .accessibilityLabel("Snooze for 30 minutes")
                        .accessibilityIdentifier("tonight.snooze")
                        .help(
                            scheduler.canSnooze
                                ? "Stay quiet for 30 minutes, then nudge immediately"
                                : "Snooze becomes available during the bedtime window"
                        )

                        Button("Pause Tonight") {
                            scheduler.muteForCurrentWindow()
                        }
                        .accessibilityLabel("Pause nudges for tonight")
                        .accessibilityIdentifier("tonight.pause")
                        .help("Stay quiet until the next bedtime window")
                    }
                }

                DisclosureGroup("One-night adjustment") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Use different times tonight", isOn: tonightOverrideBinding)
                            .accessibilityIdentifier("tonight.override.enabled")

                        if tonightOverrideBinding.wrappedValue {
                            HStack(alignment: .bottom, spacing: 14) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Begin nudging")
                                        .font(.callout.weight(.medium))
                                    DatePicker(
                                        "Tonight begin nudging",
                                        selection: timeBinding(
                                            seconds: settings.tonightOverrideStartSeconds,
                                            update: { settings.updateTonightOverrideStartSeconds($0) }
                                        ),
                                        displayedComponents: [.hourAndMinute]
                                    )
                                    .labelsHidden()
                                    .accessibilityIdentifier("tonight.override.start")
                                }

                                Image(systemName: "arrow.right")
                                    .foregroundStyle(.secondary)
                                    .padding(.bottom, 6)
                                    .accessibilityHidden(true)

                                VStack(alignment: .leading, spacing: 5) {
                                    Text(
                                        settings.tonightOverrideBedSeconds
                                            <= settings.tonightOverrideStartSeconds
                                            ? "Bedtime next day"
                                            : "Bedtime"
                                    )
                                    .font(.callout.weight(.medium))
                                    DatePicker(
                                        "Tonight bedtime",
                                        selection: timeBinding(
                                            seconds: settings.tonightOverrideBedSeconds,
                                            update: { settings.updateTonightOverrideBedSeconds($0) }
                                        ),
                                        displayedComponents: [.hourAndMinute]
                                    )
                                    .labelsHidden()
                                    .accessibilityIdentifier("tonight.override.bedtime")
                                }

                                Spacer()
                            }

                            Text("This one-night window takes priority, even on a normally inactive night.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 8)
                }
                .accessibilityIdentifier("tonight.override.disclosure")

                if !visibleStatusMessage.isEmpty {
                    Text(visibleStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityLabel("Tonight")
    }

    private var scheduleSection: some View {
        BeddyCard(title: "Bedtime window", symbol: "clock.fill", tint: BeddyPalette.blue) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Schedule name")
                    ScheduleNameTextField(
                        placeholder: "Regular",
                        value: settings.primaryScheduleName,
                        accessibilityLabel: "Primary schedule name",
                        accessibilityIdentifier: "schedule.primary.name",
                        commit: settings.updatePrimaryScheduleName
                    )
                    .frame(maxWidth: 240)
                    Spacer()
                }

                HStack(alignment: .bottom, spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Begin nudging")
                            .font(.callout.weight(.medium))
                        DatePicker(
                            "Begin nudging",
                            selection: timeBinding(
                                seconds: settings.startSeconds,
                                update: { value in settings.updateStartSeconds(value) }
                            ),
                            displayedComponents: [.hourAndMinute]
                        )
                        .labelsHidden()
                        .accessibilityLabel("Begin nudging")
                    }

                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 6)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(settings.bedSeconds <= settings.startSeconds ? "Bedtime next day" : "Bedtime")
                            .font(.callout.weight(.medium))
                        DatePicker(
                            "Bedtime",
                            selection: timeBinding(
                                seconds: settings.bedSeconds,
                                update: { value in settings.updateBedSeconds(value) }
                            ),
                            displayedComponents: [.hourAndMinute]
                        )
                        .labelsHidden()
                        .accessibilityLabel("Bedtime")
                    }

                    Spacer()
                }

                Divider()

                HStack {
                    Text("Nudge frequency")
                    Slider(value: frequencyBinding, in: 1...30, step: 1)
                        .accessibilityLabel("Base nudge frequency")
                        .accessibilityValue("\(Int(settings.frequencyMinutes)) minutes")
                    Text("\(Int(settings.frequencyMinutes)) min")
                        .monospacedDigit()
                        .frame(width: 52, alignment: .trailing)
                }

                Text("Timing varies naturally, up to \(Int(settings.frequencyMinutes * 1.7)) minutes between nudges.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Active nights")
                        .font(.callout.weight(.medium))

                    HStack(spacing: 7) {
                        ForEach(weekdayChoices) { choice in
                            let selected = settings.activeWeekdays.contains(choice.weekday)
                            Button {
                                settings.updateActiveWeekday(choice.weekday, isActive: !selected)
                            } label: {
                                weekdayLabel(choice.label, selected: selected)
                            }
                            .buttonStyle(.bordered)
                            .tint(selected ? BeddyPalette.blue : BeddyPalette.faint)
                            .accessibilityLabel("\(choice.fullLabel) nights")
                            .accessibilityValue(selected ? "Active" : "Inactive")
                            .accessibilityAddTraits(selected ? .isSelected : [])
                            .accessibilityIdentifier("schedule.weekday.\(choice.weekday)")
                        }
                    }

                    if settings.activeWeekdays.isEmpty {
                        Label("No active nights. Beddy Butler will not schedule nudges.", systemImage: "moon.slash")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }

                Toggle("Use a second schedule", isOn: alternateScheduleBinding)
                    .accessibilityLabel("Use a second schedule")
                    .accessibilityIdentifier("schedule.alternate.enabled")
                    .accessibilityHint("Allows selected weekdays or a rotating cycle to use different times")

                if settings.alternateScheduleEnabled {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Schedule name")
                            ScheduleNameTextField(
                                placeholder: "Alternate",
                                value: settings.alternateScheduleName,
                                accessibilityLabel: "Alternate schedule name",
                                accessibilityIdentifier: "schedule.alternate.name",
                                commit: settings.updateAlternateScheduleName
                            )
                            .frame(maxWidth: 240)
                            Spacer()
                        }

                        Picker("Repeat pattern", selection: alternateSchedulePatternBinding) {
                            ForEach(AlternateSchedulePattern.allCases) { pattern in
                                Text(pattern.title).tag(pattern)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("schedule.alternate.pattern")

                        if settings.alternateSchedulePattern == .selectedWeekdays {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(Self.alternateScheduleNightsTitle(settings.alternateScheduleName))
                                    .font(.callout.weight(.medium))

                                HStack(spacing: 7) {
                                    ForEach(weekdayChoices) { choice in
                                        let selected = settings.alternateScheduleWeekdays.contains(choice.weekday)
                                        Button {
                                            settings.updateAlternateScheduleWeekday(
                                                choice.weekday,
                                                isSelected: !selected
                                            )
                                        } label: {
                                            weekdayLabel(choice.label, selected: selected)
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(selected ? BeddyPalette.blue : BeddyPalette.faint)
                                        .accessibilityLabel(
                                            Self.alternateWeekdayAccessibilityLabel(
                                                scheduleName: settings.alternateScheduleName,
                                                weekdayName: choice.fullLabel
                                            )
                                        )
                                        .accessibilityValue(selected ? "Selected" : "Not selected")
                                        .accessibilityAddTraits(selected ? .isSelected : [])
                                        .accessibilityIdentifier("schedule.alternate.weekday.\(choice.weekday)")
                                    }
                                }

                                Text(
                                    "Choose any recurring nights, including an observance, community routine, or weekly shift."
                                )
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                                if settings.alternateScheduleWeekdays.isEmpty {
                                    Label(
                                        "Choose at least one night. \(settings.primaryScheduleName) currently applies every active night.",
                                        systemImage: "calendar.badge.exclamationmark"
                                    )
                                    .font(.callout)
                                    .foregroundStyle(.orange)
                                }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Rotating cycle")
                                    .font(.callout.weight(.medium))

                                VStack(alignment: .leading, spacing: 10) {
                                    Stepper(
                                        "\(settings.primaryScheduleName): \(settings.rotationPrimaryDays) days",
                                        value: rotationPrimaryDaysBinding,
                                        in: 1...28
                                    )
                                    Stepper(
                                        "\(settings.alternateScheduleName): \(settings.rotationAlternateDays) days",
                                        value: rotationAlternateDaysBinding,
                                        in: 1...28
                                    )
                                }

                                DatePicker(
                                    "Cycle begins with \(settings.primaryScheduleName)",
                                    selection: rotationAnchorDateBinding,
                                    displayedComponents: [.date]
                                )
                                .accessibilityIdentifier("schedule.rotation.anchor")

                                Text(
                                    "The cycle repeats continuously, independent of the weekday. This supports patterns such as four days on and four days off."
                                )
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        HStack(alignment: .bottom, spacing: 14) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(settings.alternateScheduleName) start")
                                    .font(.callout.weight(.medium))
                                DatePicker(
                                    "Alternate start",
                                    selection: timeBinding(
                                        seconds: settings.alternateStartSeconds,
                                        update: { settings.updateAlternateStartSeconds($0) }
                                    ),
                                    displayedComponents: [.hourAndMinute]
                                )
                                .labelsHidden()
                                .accessibilityLabel("\(settings.alternateScheduleName) nudge start time")
                                .accessibilityIdentifier("schedule.alternate.start")
                            }

                            Image(systemName: "arrow.right")
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 6)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 5) {
                                Text(
                                    settings.alternateBedSeconds <= settings.alternateStartSeconds
                                        ? "\(settings.alternateScheduleName) bedtime next day"
                                        : "\(settings.alternateScheduleName) bedtime"
                                )
                                .font(.callout.weight(.medium))
                                DatePicker(
                                    "Alternate bedtime",
                                    selection: timeBinding(
                                        seconds: settings.alternateBedSeconds,
                                        update: { settings.updateAlternateBedSeconds($0) }
                                    ),
                                    displayedComponents: [.hourAndMinute]
                                )
                                .labelsHidden()
                                .accessibilityLabel("\(settings.alternateScheduleName) bedtime")
                                .accessibilityIdentifier("schedule.alternate.bedtime")
                            }
                        }
                    }
                    .padding(12)
                    .background(
                        Color.primary.opacity(0.035),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                    }
                }

                Label(
                    "\(timeZoneIdentifier). Travel and clock changes update automatically.",
                    systemImage: "globe"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var personalitySection: some View {
        BeddyCard(title: "Nudge", symbol: "bell.badge.fill", tint: BeddyPalette.violet) {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Nudge delivery", selection: nudgeDeliveryBinding) {
                    ForEach(NudgeDelivery.allCases) { delivery in
                        Text(delivery.title).tag(delivery)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Nudge delivery")
                .accessibilityIdentifier("nudge.delivery")
                .accessibilityHint("Choose an audible reminder, a persistent visual badge, or both")

                Text(settings.nudgeDelivery.guidance)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if settings.nudgeDelivery.includesSound {
                    Divider()

                    Picker("Butler personality", selection: personalityBinding) {
                        ForEach(ButlerPersonality.allCases) { personality in
                            Text(personality.title).tag(personality)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Butler personality")
                    .accessibilityIdentifier("nudge.personality")
                    .accessibilityHint("Selects the style of voice reminder")
                }

                HStack(alignment: .center, spacing: 18) {
                    if settings.nudgeDelivery.includesSound {
                        AnimatedButlerArtwork(
                            personality: settings.personality,
                            presentation: .preview,
                            viewportHeight: scrollViewportHeight
                        )
                    } else {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 48, weight: .medium))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 144, height: 172)
                            .accessibilityHidden(true)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(previewGuidance)
                            .font(.body.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            scheduler.previewNudge(settings.personality)
                        } label: {
                            Label(previewLabel, systemImage: previewSymbol)
                        }
                        .primaryGlassButton(tint: BeddyPalette.violet)
                        .accessibilityLabel(previewLabel)
                        .accessibilityIdentifier("nudge.preview")
                        .accessibilityHint(previewAccessibilityHint)
                    }
                }

                if settings.nudgeDelivery.includesSound {
                    Divider()

                    HStack(spacing: 10) {
                        Label("Voice volume", systemImage: "speaker.wave.2")
                        Slider(value: volumeBinding, in: 0...1, step: 0.05)
                            .accessibilityLabel("Voice volume")
                            .accessibilityValue("\(volumePercent) percent")
                            .accessibilityIdentifier("nudge.volume")
                        Text("\(volumePercent)%")
                            .monospacedDigit()
                            .frame(width: 46, alignment: .trailing)
                    }
                }

                if settings.nudgeDelivery.includesVisual {
                    Divider()

                    Toggle("Also show a silent Notification Center alert", isOn: notificationAlertBinding)
                        .accessibilityLabel("Show silent Notification Center alerts")
                        .accessibilityIdentifier("nudge.notifications")
                        .accessibilityHint("Adds a local visual alert with acknowledge, snooze, and pause actions")

                    if notificationManager.authorizationState == .denied {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(
                                "Notification permission is disabled in System Settings. The menu-bar badge still works.",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.callout)
                            .foregroundStyle(.orange)

                            Button("Open Notification Settings") {
                                notificationManager.openSystemSettings()
                            }
                            .accessibilityIdentifier("nudge.openNotificationSettings")
                        }
                    }

                    if let error = notificationManager.lastError {
                        Label(error, systemImage: "xmark.octagon.fill")
                            .font(.callout)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var behaviorSection: some View {
        BeddyCard(title: "Behavior", symbol: "dial.medium", tint: BeddyPalette.warm) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Progressive mode", isOn: progressiveBinding)
                    .fontWeight(.medium)
                    .accessibilityLabel("Progressive mode")
                    .accessibilityIdentifier("behavior.progressive")
                    .accessibilityHint("Escalates the selected personality after every two or three nudges")
                    .disabled(!settings.nudgeDelivery.includesSound)

                Label("Shy  →  Insistent  →  Zombie", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)

                Text(
                    settings.nudgeDelivery.includesSound
                        ? "Every few nudges, the butler grows more persuasive. Each bedtime window resets the voice."
                        : "Progressive mode applies when sound is enabled. Visual badges remain persistent until acknowledged."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var startupSection: some View {
        BeddyCard(title: "Startup", symbol: "power", tint: BeddyPalette.zombie) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Open Beddy Butler at login", isOn: launchAtLoginBinding)
                    .accessibilityLabel("Open Beddy Butler at login")
                    .accessibilityIdentifier("startup.openAtLogin")
                    .accessibilityHint("Lets Beddy Butler begin waiting in the menu bar after you sign in")

                if loginItemManager.state == .requiresApproval {
                    Label("macOS is waiting for approval in Login Items.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Button("Open Login Items Settings") {
                        loginItemManager.openSystemSettings()
                    }
                    .accessibilityLabel("Open Login Items Settings")
                    .accessibilityIdentifier("startup.openSettings")
                } else if loginItemManager.state == .unavailable {
                    Label("Launch at login becomes available in a signed app build.", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }

                if let error = loginItemManager.lastError {
                    Label(error, systemImage: "xmark.octagon.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }

                Divider()

                HStack(spacing: 12) {
                    Button("Show Welcome Guide") {
                        settings.replayOnboarding()
                    }
                    .accessibilityIdentifier("startup.replayOnboarding")
                    .accessibilityHint("Shows the original setup guidance without changing settings")

                    Button("Restore Recommended Defaults…", role: .destructive) {
                        showingRestoreDefaultsConfirmation = true
                    }
                    .accessibilityIdentifier("startup.restoreDefaults")
                    .accessibilityHint("Asks before restoring Beddy Butler settings")
                }

                Text("Restoring defaults keeps Open at Login and macOS notification permission unchanged.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog(
            "Restore recommended defaults?",
            isPresented: $showingRestoreDefaultsConfirmation
        ) {
            Button("Restore Recommended Defaults", role: .destructive) {
                notificationManager.setEnabled(false, settings: settings)
                settings.restoreRecommendedDefaults()
                scheduler.recalculate()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Schedules, personality, volume, nudge options, pauses, one night changes, and pending visual nudges will return to their original recommended values."
            )
        }
    }

    private var footer: some View {
        HStack {
            Label("Changes save automatically.", systemImage: "checkmark.circle.fill")
            Spacer()
            Text("\(ApplicationMetadata.displayName) \(ApplicationMetadata.shortVersion)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func weekdayLabel(_ label: String, selected: Bool) -> some View {
        HStack(spacing: 4) {
            if selected {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
            }
            Text(label)
        }
        .frame(minWidth: 34)
        .contentShape(Rectangle())
    }

    static func alternateScheduleNightsTitle(_ scheduleName: String) -> String {
        "\(scheduleName) nights"
    }

    static func alternateWeekdayAccessibilityLabel(
        scheduleName: String,
        weekdayName: String
    ) -> String {
        "\(scheduleName) schedule on \(weekdayName) nights"
    }

    private var headerStatusTitle: String {
        if scheduler.visualNudgePending {
            return "Nudge waiting"
        }
        if settings.isMuted() {
            return "Paused"
        }
        if scheduler.nextNudge != nil {
            return "On duty"
        }
        return "Needs a schedule"
    }

    private var headerStatusSymbol: String {
        if scheduler.visualNudgePending {
            return "bell.badge.fill"
        }
        if settings.isMuted() {
            return "pause.fill"
        }
        if scheduler.nextNudge != nil {
            return "checkmark.circle.fill"
        }
        return "exclamationmark.circle.fill"
    }

    private var headerStatusTint: Color {
        if scheduler.visualNudgePending {
            return BeddyPalette.warm
        }
        if settings.isMuted() {
            return BeddyPalette.warm
        }
        if scheduler.nextNudge != nil {
            return BeddyPalette.success
        }
        return BeddyPalette.faint
    }

    private var scheduleHeading: String {
        if scheduler.visualNudgePending {
            return
                scheduler.pendingVisualNudgeCount == 1
                ? "Visual bedtime nudge waiting"
                : "\(scheduler.pendingVisualNudgeCount) visual bedtime nudges waiting"
        }
        if let mutedUntil = settings.mutedUntil, settings.isMuted() {
            return "Paused until \(LocalizedScheduleText.time(mutedUntil))"
        }
        if let nextNudge = scheduler.nextNudge {
            return "Next nudge at \(LocalizedScheduleText.time(nextNudge))"
        }
        return "Waiting for a valid bedtime window"
    }

    private var scheduleDetail: String {
        if scheduler.visualNudgePending {
            return "The menu-bar badge and count remain until you acknowledge them."
        }
        if settings.isMuted() {
            return "Beddy Butler will remain quiet, then continue automatically."
        }
        guard let nextNudge = scheduler.nextNudge else {
            return "Adjust the bedtime window below to resume scheduling."
        }
        let relative = RelativeDateTimeFormatter().localizedString(for: nextNudge, relativeTo: Date())
        let presentation =
            switch settings.nudgeDelivery {
            case .sound:
                "\(scheduler.nextPersonality.title) voice"
            case .visual:
                "Visual badge"
            case .both:
                "\(scheduler.nextPersonality.title) voice and visual badge"
            }
        return "\(presentation), \(relative)."
    }

    private var previewLabel: String {
        switch settings.nudgeDelivery {
        case .sound:
            settings.personality.sampleLabel
        case .visual:
            "Preview Visual Badge"
        case .both:
            "Preview Sound + Badge"
        }
    }

    private var previewSymbol: String {
        settings.nudgeDelivery.includesSound ? "speaker.wave.2.fill" : "bell.badge.fill"
    }

    private var previewGuidance: String {
        settings.nudgeDelivery.includesSound
            ? settings.personality.guidance
            : "A clear, silent reminder that stays in the menu bar until you acknowledge it."
    }

    private var previewAccessibilityHint: String {
        switch settings.nudgeDelivery {
        case .sound:
            "Plays one randomly selected voice clip at the chosen volume"
        case .visual:
            "Shows a silent menu-bar badge that remains until acknowledged"
        case .both:
            "Plays one randomly selected voice clip and shows a menu-bar badge"
        }
    }

    private var volumePercent: Int {
        Int((settings.voiceVolume * 100).rounded())
    }

    private var visibleStatusMessage: String {
        if scheduler.lastEvent != "Schedule is active." {
            return scheduler.lastEvent
        }
        if settings.activeWeekdays.isEmpty {
            return "No active nights are selected."
        }
        return scheduler.canSnooze
            ? "Your bedtime window is active."
            : "Waiting for tonight's bedtime window."
    }

    private var weekdayChoices: [WeekdayChoice] {
        let calendar = Calendar.autoupdatingCurrent
        let short = calendar.shortStandaloneWeekdaySymbols
        let full = calendar.weekdaySymbols
        return [2, 3, 4, 5, 6, 7, 1].map { weekday in
            let index = weekday - 1
            return WeekdayChoice(
                weekday: weekday,
                label: short.indices.contains(index) ? short[index] : "?",
                fullLabel: full.indices.contains(index) ? full[index] : "Day"
            )
        }
    }

    private func timeBinding(seconds: Int, update: @escaping (Int) -> Void) -> Binding<Date> {
        Binding(
            get: { WallClockTime.date(for: seconds) },
            set: { update(WallClockTime.seconds(from: $0)) }
        )
    }

    private var frequencyBinding: Binding<Double> {
        Binding(
            get: { settings.frequencyMinutes },
            set: { value in settings.updateFrequencyMinutes(value) }
        )
    }

    private var personalityBinding: Binding<ButlerPersonality> {
        Binding(
            get: { settings.personality },
            set: { value in settings.updatePersonality(value) }
        )
    }

    private var progressiveBinding: Binding<Bool> {
        Binding(
            get: { settings.progressiveMode },
            set: { value in settings.updateProgressiveMode(value) }
        )
    }

    private var alternateScheduleBinding: Binding<Bool> {
        Binding(
            get: { settings.alternateScheduleEnabled },
            set: { settings.updateAlternateScheduleEnabled($0) }
        )
    }

    private var tonightOverrideBinding: Binding<Bool> {
        Binding(
            get: {
                settings.tonightOverrideIsActive()
            },
            set: { enabled in
                if enabled {
                    settings.enableTonightOverride()
                } else {
                    settings.clearTonightOverride()
                }
            }
        )
    }

    private var alternateSchedulePatternBinding: Binding<AlternateSchedulePattern> {
        Binding(
            get: { settings.alternateSchedulePattern },
            set: { settings.updateAlternateSchedulePattern($0) }
        )
    }

    private var rotationAnchorDateBinding: Binding<Date> {
        Binding(
            get: { settings.rotationAnchorDate },
            set: { settings.updateRotationAnchorDate($0) }
        )
    }

    private var rotationPrimaryDaysBinding: Binding<Int> {
        Binding(
            get: { settings.rotationPrimaryDays },
            set: { settings.updateRotationPrimaryDays($0) }
        )
    }

    private var rotationAlternateDaysBinding: Binding<Int> {
        Binding(
            get: { settings.rotationAlternateDays },
            set: { settings.updateRotationAlternateDays($0) }
        )
    }

    private var notificationAlertBinding: Binding<Bool> {
        Binding(
            get: { settings.notificationAlertsEnabled },
            set: { notificationManager.setEnabled($0, settings: settings) }
        )
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { settings.voiceVolume },
            set: { value in settings.updateVoiceVolume(value) }
        )
    }

    private var nudgeDeliveryBinding: Binding<NudgeDelivery> {
        Binding(
            get: { settings.nudgeDelivery },
            set: { value in settings.updateNudgeDelivery(value) }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { loginItemManager.isEnabled },
            set: { value in loginItemManager.setEnabled(value) }
        )
    }
}
