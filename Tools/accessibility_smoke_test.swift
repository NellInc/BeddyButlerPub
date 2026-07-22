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

try process.run()
defer {
    if process.isRunning {
        process.terminate()
        process.waitUntilExit()
    }
    UserDefaults(suiteName: defaultsSuite)?.removePersistentDomain(forName: defaultsSuite)
}

let app = AXUIElementCreateApplication(process.processIdentifier)
let deadline = Date().addingTimeInterval(12)
var elements: [AXUIElement] = []
repeat {
    Thread.sleep(forTimeInterval: 0.25)
    elements = descendants(of: app)
} while elements.count < 10 && process.isRunning && Date() < deadline

guard process.isRunning else {
    let data = log.fileHandleForReading.readDataToEndOfFile()
    fputs("Beddy Butler exited during the accessibility check.\n", stderr)
    if let output = String(data: data, encoding: .utf8), !output.isEmpty {
        fputs(output, stderr)
    }
    exit(1)
}

let identifiers = Set(
    elements.compactMap {
        attribute(kAXIdentifierAttribute as CFString, of: $0) as? String
    }
)
let requiredIdentifiers: Set<String> = [
    "onboarding.start",
    "tonight.override.disclosure",
    "schedule.primary.name",
    "schedule.alternate.enabled",
    "nudge.delivery",
    "startup.openAtLogin",
]
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
    exit(1)
}
guard missing.isEmpty else {
    fputs("Missing accessibility identifiers: \(missing.sorted().joined(separator: ", "))\n", stderr)
    exit(1)
}

guard
    let menuBarItem = elements.first(where: {
        (attribute(kAXRoleAttribute as CFString, of: $0) as? String)
            == (kAXMenuBarItemRole as String)
            && (attribute(kAXDescriptionAttribute as CFString, of: $0) as? String)
                == "Beddy Butler"
    }),
    AXUIElementPerformAction(menuBarItem, kAXPressAction as CFString) == .success
else {
    fputs("The Beddy Butler menu-bar item could not be opened through accessibility.\n", stderr)
    exit(1)
}

let popoverDeadline = Date().addingTimeInterval(4)
let popoverIdentifiers: Set<String> = [
    "popover.preview",
    "popover.snooze",
    "popover.pause",
    "popover.preferences",
    "popover.quit",
]
var visiblePopoverIdentifiers: Set<String> = []
repeat {
    Thread.sleep(forTimeInterval: 0.2)
    visiblePopoverIdentifiers = Set(
        descendants(of: app).compactMap {
            attribute(kAXIdentifierAttribute as CFString, of: $0) as? String
        }
    )
} while !popoverIdentifiers.isSubset(of: visiblePopoverIdentifiers) && Date() < popoverDeadline

let missingPopoverControls = popoverIdentifiers.subtracting(visiblePopoverIdentifiers)
guard missingPopoverControls.isEmpty else {
    fputs(
        "Missing Tonight-panel controls: \(missingPopoverControls.sorted().joined(separator: ", "))\n",
        stderr
    )
    exit(1)
}

print(
    "Accessibility smoke passed: \(elements.count) elements, "
        + "\(requiredIdentifiers.count + popoverIdentifiers.count) required controls"
)
