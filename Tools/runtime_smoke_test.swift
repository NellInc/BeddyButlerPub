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

let defaultsSuitePrefix = "BeddyButler.RuntimeSmoke."
// A signed candidate runs in the App Sandbox and writes its suite into its
// container rather than the user's preferences folder, so clean up both.
let candidateBundleIdentifier =
    Bundle(
        url: executable.resolvingSymlinksInPath()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    )?.bundleIdentifier

func isOwnedDefaultsSuite(_ suiteName: String) -> Bool {
    guard suiteName.hasPrefix(defaultsSuitePrefix) else { return false }
    return UUID(uuidString: String(suiteName.dropFirst(defaultsSuitePrefix.count))) != nil
}

func preferenceFiles(for suiteName: String) -> [URL] {
    let library = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library", isDirectory: true)
    var directories = [library.appendingPathComponent("Preferences", isDirectory: true)]
    if let candidateBundleIdentifier {
        directories.append(
            library.appendingPathComponent("Containers", isDirectory: true)
                .appendingPathComponent(candidateBundleIdentifier, isDirectory: true)
                .appendingPathComponent("Data/Library/Preferences", isDirectory: true)
        )
    }
    return directories.map { $0.appendingPathComponent("\(suiteName).plist") }
}

func deleteDefaultsDomain(_ domain: String) -> Bool {
    let delete = Process()
    delete.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
    delete.arguments = ["delete", domain]
    let deleteError = Pipe()
    delete.standardOutput = FileHandle.nullDevice
    delete.standardError = deleteError
    do {
        try delete.run()
    } catch {
        fputs("Runtime-smoke defaults cleanup failed: \(error.localizedDescription)\n", stderr)
        return false
    }
    let deleteMessage = String(
        decoding: deleteError.fileHandleForReading.readDataToEndOfFile(),
        as: UTF8.self
    )
    delete.waitUntilExit()
    // Only one of the two locations holds the suite, so `defaults` reports the
    // other as a missing domain rather than a failure to clear.
    guard delete.terminationStatus == 0 || deleteMessage.contains("not found") else {
        fputs("Runtime-smoke defaults cleanup command failed.\n", stderr)
        return false
    }
    return true
}

@discardableResult
func clearDefaultsSuite(named suiteName: String) -> Bool {
    guard isOwnedDefaultsSuite(suiteName) else {
        fputs("Refusing to clear an unexpected runtime-smoke defaults domain.\n", stderr)
        return false
    }
    let preferenceFiles = preferenceFiles(for: suiteName)
    // Clear each plist through cfprefsd first, so a flush still pending from
    // the terminated child cannot recreate the file after it is removed.
    var cleared = preferenceFiles.map {
        deleteDefaultsDomain($0.deletingPathExtension().path)
    }.allSatisfy { $0 }

    Thread.sleep(forTimeInterval: 0.2)
    for preferenceFile in preferenceFiles
    where FileManager.default.fileExists(atPath: preferenceFile.path) {
        do {
            // The child is terminated before cleanup, and the UUID-qualified suite
            // belongs solely to this probe. Remove any cfprefsd file left behind by
            // the domain deletion, including the expected defaults the app seeded.
            try FileManager.default.removeItem(at: preferenceFile)
        } catch {
            fputs("Runtime-smoke defaults cleanup failed: \(error.localizedDescription)\n", stderr)
        }
    }
    Thread.sleep(forTimeInterval: 1)
    for preferenceFile in preferenceFiles
    where FileManager.default.fileExists(atPath: preferenceFile.path) {
        fputs("Runtime-smoke defaults remain at \(preferenceFile.path)\n", stderr)
        cleared = false
    }
    return cleared
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
    finish(1)
}

guard
    let preferencesWindow,
    let boundsDictionary = preferencesWindow[kCGWindowBounds as String] as? NSDictionary,
    let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
    bounds.width >= 600,
    bounds.height >= 640
else {
    fputs("The resizable preferences window did not appear within 10 seconds.\n", stderr)
    finish(1)
}

guard cleanUp() else {
    exit(1)
}

print(
    "Runtime smoke passed: PID \(process.processIdentifier), "
        + "preferences \(Int(bounds.width))x\(Int(bounds.height))"
)
