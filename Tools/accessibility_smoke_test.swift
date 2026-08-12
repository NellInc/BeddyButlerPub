#!/usr/bin/env swift
import ApplicationServices
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: Tools/accessibility_smoke_test.swift <Beddy Butler executable>\n", stderr)
    exit(64)
}

guard AXIsProcessTrusted() else {
    fputs("Accessibility permission is required for the terminal running this check.\n", stderr)
    exit(77)
}

let executable = URL(fileURLWithPath: CommandLine.arguments[1])
guard FileManager.default.isExecutableFile(atPath: executable.path) else {
    fputs("The supplied Beddy Butler executable is not runnable.\n", stderr)
    exit(66)
}

func attribute(_ name: CFString, of element: AXUIElement) -> AnyObject? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else {
        return nil
    }
    return value
}

func axValueAttribute(_ name: CFString, of element: AXUIElement) -> AXValue? {
    guard let value = attribute(name, of: element), CFGetTypeID(value) == AXValueGetTypeID()
    else {
        return nil
    }
    return unsafeBitCast(value, to: AXValue.self)
}

func descendants(of root: AXUIElement, limit: Int = 2_000) -> [AXUIElement] {
    var result: [AXUIElement] = []
    var queue = [root]
    while !queue.isEmpty, result.count < limit {
        let element = queue.removeFirst()
        result.append(element)
        if let children = attribute(kAXChildrenAttribute as CFString, of: element) as? [AXUIElement] {
            queue.append(contentsOf: children)
        }
    }
    return result
}

let defaultsSuite = "BeddyButler.AccessibilitySmoke.\(UUID().uuidString)"
let process = Process()
process.executableURL = executable
process.environment = ProcessInfo.processInfo.environment.merging(
    [
        "BEDDY_BUTLER_DEFAULTS_SUITE": defaultsSuite,
        "BEDDY_BUTLER_OPEN_PREFERENCES": "1",
    ],
    uniquingKeysWith: { _, requested in requested }
)
let log = Pipe()
process.standardOutput = log
process.standardError = log

let defaultsSuitePrefix = "BeddyButler.AccessibilitySmoke."

func isOwnedDefaultsSuite(_ suiteName: String) -> Bool {
    guard suiteName.hasPrefix(defaultsSuitePrefix) else { return false }
    return UUID(uuidString: String(suiteName.dropFirst(defaultsSuitePrefix.count))) != nil
}

@discardableResult
func clearDefaultsSuite(named suiteName: String) -> Bool {
    guard isOwnedDefaultsSuite(suiteName) else {
        fputs("Refusing to clear an unexpected accessibility-smoke defaults domain.\n", stderr)
        return false
    }
    let delete = Process()
    delete.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
    delete.arguments = ["delete", suiteName]
    delete.standardOutput = FileHandle.nullDevice
    delete.standardError = FileHandle.nullDevice
    do {
        try delete.run()
    } catch {
        fputs("Accessibility-smoke defaults cleanup failed: \(error.localizedDescription)\n", stderr)
        return false
    }
    delete.waitUntilExit()
    guard delete.terminationStatus == 0 else {
        fputs("Accessibility-smoke defaults cleanup command failed.\n", stderr)
        return false
    }

    Thread.sleep(forTimeInterval: 0.2)
    let preferenceFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Preferences", isDirectory: true)
        .appendingPathComponent("\(suiteName).plist")
    guard FileManager.default.fileExists(atPath: preferenceFile.path) else { return true }
    do {
        // The child is terminated before cleanup, and the UUID-qualified suite
        // belongs solely to this probe. Remove any cfprefsd file left behind by
        // the domain deletion, including the expected defaults the app seeded.
        try FileManager.default.removeItem(at: preferenceFile)
        return !FileManager.default.fileExists(atPath: preferenceFile.path)
    } catch {
        fputs("Accessibility-smoke defaults cleanup failed: \(error.localizedDescription)\n", stderr)
        return false
    }
}

try process.run()
var cleanupCompleted = false
func cleanUp() -> Bool {
    if cleanupCompleted { return true }
    if process.isRunning {
        process.terminate()
        process.waitUntilExit()
    }
    cleanupCompleted = clearDefaultsSuite(named: defaultsSuite)
    return cleanupCompleted
}
defer { _ = cleanUp() }

func finish(_ status: Int32) -> Never {
    let cleanupSucceeded = cleanUp()
    exit(status == 0 && !cleanupSucceeded ? 1 : status)
}

let app = AXUIElementCreateApplication(process.processIdentifier)
let deadline = Date().addingTimeInterval(12)
let requiredSemantics: [String: (role: String, description: String)] = [
    "onboarding.start": (kAXButtonRole as String, "Start Beddy Butler"),
    "tonight.override.disclosure": (kAXDisclosureTriangleRole as String, "One-night adjustment"),
    "schedule.primary.name": (kAXTextFieldRole as String, "Primary schedule name"),
    "schedule.alternate.enabled": (kAXCheckBoxRole as String, "Use a second schedule"),
    "nudge.delivery": (kAXRadioGroupRole as String, "Nudge delivery"),
    "startup.openAtLogin": (kAXCheckBoxRole as String, "Open Beddy Butler at login"),
    "startup.replayOnboarding": (kAXButtonRole as String, "Show Welcome Guide"),
    "startup.restoreDefaults": (kAXButtonRole as String, "Restore Recommended Defaults…"),
]
let requiredIdentifiers = Set(requiredSemantics.keys)
var elements: [AXUIElement] = []
var identifiers: Set<String> = []
repeat {
    Thread.sleep(forTimeInterval: 0.25)
    elements = descendants(of: app)
    identifiers = Set(
        elements.compactMap {
            attribute(kAXIdentifierAttribute as CFString, of: $0) as? String
        }
    )
} while !requiredIdentifiers.isSubset(of: identifiers) && process.isRunning && Date() < deadline

guard process.isRunning else {
    let data = log.fileHandleForReading.readDataToEndOfFile()
    fputs("Beddy Butler exited during the accessibility check.\n", stderr)
    if let output = String(data: data, encoding: .utf8), !output.isEmpty {
        fputs(output, stderr)
    }
    finish(1)
}

let missing = requiredIdentifiers.subtracting(identifiers)

let windowTitles: Set<String> = Set(
    elements.compactMap {
        guard
            (attribute(kAXRoleAttribute as CFString, of: $0) as? String)
                == (kAXWindowRole as String)
        else {
            return nil
        }
        return attribute(kAXTitleAttribute as CFString, of: $0) as? String
    }
)

guard windowTitles.contains("Beddy Butler Preferences") else {
    fputs("The preferences window was absent from the accessibility hierarchy.\n", stderr)
    finish(1)
}
guard missing.isEmpty else {
    fputs("Missing accessibility identifiers: \(missing.sorted().joined(separator: ", "))\n", stderr)
    finish(1)
}

var semanticFailures: [String] = []
for (identifier, expected) in requiredSemantics {
    guard
        let element = elements.first(where: {
            (attribute(kAXIdentifierAttribute as CFString, of: $0) as? String) == identifier
        })
    else {
        continue
    }
    let role = attribute(kAXRoleAttribute as CFString, of: element) as? String
    let description = attribute(kAXDescriptionAttribute as CFString, of: element) as? String
    if role != expected.role || description != expected.description {
        semanticFailures.append(
            "\(identifier) expected \(expected.role)/\(expected.description), "
                + "found \(role ?? "nil")/\(description ?? "nil")"
        )
    }
}
guard semanticFailures.isEmpty else {
    fputs("Accessibility semantic failures: \(semanticFailures.sorted().joined(separator: "; "))\n", stderr)
    finish(1)
}

guard
    let menuBarItem = elements.first(where: {
        (attribute(kAXRoleAttribute as CFString, of: $0) as? String)
            == (kAXMenuBarItemRole as String)
            && (attribute(kAXDescriptionAttribute as CFString, of: $0) as? String)
                == "Beddy Butler"
    }),
    let positionValue = axValueAttribute(kAXPositionAttribute as CFString, of: menuBarItem),
    let sizeValue = axValueAttribute(kAXSizeAttribute as CFString, of: menuBarItem)
else {
    fputs("The Beddy Butler menu-bar item could not be located for a physical click.\n", stderr)
    finish(1)
}

var menuBarPosition = CGPoint.zero
var menuBarSize = CGSize.zero
guard AXValueGetValue(positionValue, .cgPoint, &menuBarPosition),
    AXValueGetValue(sizeValue, .cgSize, &menuBarSize)
else {
    fputs("The Beddy Butler menu-bar item did not expose clickable bounds.\n", stderr)
    finish(1)
}

let originalPointerPosition = CGEvent(source: nil)?.location
let menuBarCentre = CGPoint(
    x: menuBarPosition.x + menuBarSize.width / 2,
    y: menuBarPosition.y + menuBarSize.height / 2
)
guard
    let mouseDown = CGEvent(
        mouseEventSource: nil,
        mouseType: .leftMouseDown,
        mouseCursorPosition: menuBarCentre,
        mouseButton: .left
    ),
    let mouseUp = CGEvent(
        mouseEventSource: nil,
        mouseType: .leftMouseUp,
        mouseCursorPosition: menuBarCentre,
        mouseButton: .left
    )
else {
    fputs("The physical menu-bar click events could not be created.\n", stderr)
    finish(1)
}
mouseDown.post(tap: .cghidEventTap)
Thread.sleep(forTimeInterval: 0.06)
mouseUp.post(tap: .cghidEventTap)
if let originalPointerPosition,
    let restorePointer = CGEvent(
        mouseEventSource: nil,
        mouseType: .mouseMoved,
        mouseCursorPosition: originalPointerPosition,
        mouseButton: .left
    )
{
    restorePointer.post(tap: .cghidEventTap)
}

let popoverIdentifiers: Set<String> = [
    "popover.preview",
    "popover.snooze",
    "popover.pause",
    "popover.preferences",
    "popover.about",
    "popover.quit",
]
var visiblePopoverIdentifiers: Set<String> = []
var popoverDeadline = Date().addingTimeInterval(4)
repeat {
    Thread.sleep(forTimeInterval: 0.2)
    visiblePopoverIdentifiers = Set(
        descendants(of: app).compactMap {
            attribute(kAXIdentifierAttribute as CFString, of: $0) as? String
        }
    )
} while !popoverIdentifiers.isSubset(of: visiblePopoverIdentifiers) && Date() < popoverDeadline

var usedAccessibilityFallback = false
if !popoverIdentifiers.isSubset(of: visiblePopoverIdentifiers) {
    // A newly launched status item can be placed behind a MacBook notch when
    // the current menu bar is crowded. The app remains operable through its
    // standard accessibility press action, so use that as a deterministic
    // fallback while preserving the physical-click attempt above.
    if AXUIElementPerformAction(menuBarItem, kAXPressAction as CFString) == .success {
        usedAccessibilityFallback = true
        popoverDeadline = Date().addingTimeInterval(4)
        repeat {
            Thread.sleep(forTimeInterval: 0.2)
            visiblePopoverIdentifiers = Set(
                descendants(of: app).compactMap {
                    attribute(kAXIdentifierAttribute as CFString, of: $0) as? String
                }
            )
        } while !popoverIdentifiers.isSubset(of: visiblePopoverIdentifiers)
            && Date() < popoverDeadline
    }
}

let missingPopoverControls = popoverIdentifiers.subtracting(visiblePopoverIdentifiers)
guard missingPopoverControls.isEmpty else {
    fputs(
        "Missing Tonight-panel controls: \(missingPopoverControls.sorted().joined(separator: ", "))\n",
        stderr
    )
    finish(1)
}

guard
    let aboutButton = descendants(of: app).first(where: {
        (attribute(kAXIdentifierAttribute as CFString, of: $0) as? String) == "popover.about"
    }),
    AXUIElementPerformAction(aboutButton, kAXPressAction as CFString) == .success
else {
    fputs("The Tonight-panel About control could not be activated.\n", stderr)
    finish(1)
}

let requiredCredit = "Design and engineering by Nell Watson and David Garces."
let requiredQACredit = "QA by Filip Alimpić."
var aboutStrings: Set<String> = []
let aboutDeadline = Date().addingTimeInterval(4)
repeat {
    Thread.sleep(forTimeInterval: 0.2)
    aboutStrings = Set(
        descendants(of: app).flatMap { element in
            [
                attribute(kAXTitleAttribute as CFString, of: element) as? String,
                attribute(kAXValueAttribute as CFString, of: element) as? String,
                attribute(kAXDescriptionAttribute as CFString, of: element) as? String,
            ].compactMap { $0 }
        }
    )
} while !(aboutStrings.contains(where: { $0.contains(requiredCredit) })
    && aboutStrings.contains(where: { $0.contains(requiredQACredit) }))
    && process.isRunning && Date() < aboutDeadline

guard aboutStrings.contains(where: { $0.contains(requiredCredit) }) else {
    fputs("The About panel did not expose the required design and engineering credit.\n", stderr)
    finish(1)
}

guard aboutStrings.contains(where: { $0.contains(requiredQACredit) }) else {
    fputs("The About panel did not expose the required QA credit.\n", stderr)
    finish(1)
}

guard cleanUp() else {
    exit(1)
}
print(
    "Accessibility smoke passed: \(elements.count) elements, "
        + "\(requiredIdentifiers.count + popoverIdentifiers.count) required controls"
        + (usedAccessibilityFallback
            ? " (accessibility press fallback used for the current menu-bar layout)"
            : "")
)
