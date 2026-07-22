#!/usr/bin/env swift
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: Tools/runtime_smoke_test.swift <Beddy Butler executable>\n", stderr)
    exit(64)
}

let executable = URL(fileURLWithPath: CommandLine.arguments[1])
guard FileManager.default.isExecutableFile(atPath: executable.path) else {
    fputs("The supplied Beddy Butler executable is not runnable.\n", stderr)
    exit(66)
}

let process = Process()
process.executableURL = executable
let defaultsSuite = "BeddyButler.RuntimeSmoke.\(UUID().uuidString)"
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

let deadline = Date().addingTimeInterval(10)
var preferencesWindow: [String: Any]?
repeat {
    Thread.sleep(forTimeInterval: 0.25)
    let windows =
        CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []
    preferencesWindow = windows.first { window in
        (window[kCGWindowOwnerPID as String] as? pid_t) == process.processIdentifier
            && (window[kCGWindowName as String] as? String) == "Beddy Butler Preferences"
    }
} while preferencesWindow == nil && process.isRunning && Date() < deadline

guard process.isRunning else {
    let data = log.fileHandleForReading.readDataToEndOfFile()
    fputs("Beddy Butler exited during launch.\n", stderr)
    if let output = String(data: data, encoding: .utf8), !output.isEmpty {
        fputs(output, stderr)
    }
    exit(1)
}

guard
    let preferencesWindow,
    let boundsDictionary = preferencesWindow[kCGWindowBounds as String] as? NSDictionary,
    let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
    bounds.width >= 600,
    bounds.height >= 640
else {
    fputs("The resizable preferences window did not appear within 10 seconds.\n", stderr)
    exit(1)
}

print(
    "Runtime smoke passed: PID \(process.processIdentifier), "
        + "preferences \(Int(bounds.width))x\(Int(bounds.height))"
)
