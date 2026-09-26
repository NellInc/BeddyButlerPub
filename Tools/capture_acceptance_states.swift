#!/usr/bin/env swift
import AppKit
import CryptoKit
import Foundation
import ImageIO

struct CaptureState {
    let name: String
    let values: [String: Any]
}

struct CaptureError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

guard CommandLine.arguments.count == 3 else {
    fputs(
        "Usage: Tools/capture_acceptance_states.swift <Beddy Butler executable> <output directory>\n",
        stderr
    )
    exit(64)
}

let executable = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
let outputDirectory = URL(
    fileURLWithPath: CommandLine.arguments[2],
    isDirectory: true
).standardizedFileURL
guard FileManager.default.isExecutableFile(atPath: executable.path) else {
    fputs("The supplied Beddy Butler executable is not runnable.\n", stderr)
    exit(66)
}

// Whole seconds, so a bedtime seeded from the wall clock ends exactly at `windowEnd`.
let now = Date(timeIntervalSinceReferenceDate: Date().timeIntervalSinceReferenceDate.rounded(.down))
let calendar = Calendar.autoupdatingCurrent
let components = calendar.dateComponents([.hour, .minute, .second], from: now)
let wallSeconds = (components.hour ?? 0) * 3600 + (components.minute ?? 0) * 60 + (components.second ?? 0)
// States that need a live bedtime window use one that began 5 minutes ago and ends in an hour.
let windowStartValue = (wallSeconds + 86400 - 300) % 86400
let windowBedValue = (wallSeconds + 3600) % 86400
let windowEnd = now.addingTimeInterval(3600)
// The "paused" state keeps the default 21:30 to 23:00 window and pauses the containing or next one.
let defaultBedtime = DateComponents(hour: 23, minute: 0, second: 0)
guard
    let nextDefaultWindowEnd = calendar.nextDate(
        after: now,
        matching: defaultBedtime,
        matchingPolicy: .nextTime
    )
else {
    fputs("Could not compute the next default bedtime.\n", stderr)
    exit(70)
}
let states = [
    CaptureState(
        name: "finished-tonight",
        values: [
            "onboardingVersion": 1,
            "startTimeValue": windowStartValue,
            "bedTimeValue": windowBedValue,
            "nudgeDelivery": "both",
            "isMuted": true,
            "mutedUntil": windowEnd,
            "finishedWindowEnd": windowEnd,
        ]
    ),
    CaptureState(
        name: "active-evening",
        values: [
            "onboardingVersion": 1,
            "startTimeValue": windowStartValue,
            "bedTimeValue": windowBedValue,
            "nudgeDelivery": "both",
            "progressive": true,
            "maximumPersonality": "insistent",
            "snoozeMinutes": 20,
        ]
    ),
    CaptureState(
        name: "paused-pending",
        values: [
            // A snooze that reaches bedtime pauses the rest of the window and keeps waiting badges.
            "onboardingVersion": 1,
            "startTimeValue": windowStartValue,
            "bedTimeValue": windowBedValue,
            "nudgeDelivery": "visual",
            "isMuted": true,
            "mutedUntil": windowEnd,
            "mutedWholeWindow": true,
            "pendingVisualNudgeCount": 2,
            "lastVisualNudgeAt": now.addingTimeInterval(-60),
        ]
    ),
    CaptureState(
        name: "snoozed-pending",
        values: [
            // A 20-minute snooze inside the window, with waiting badges.
            "onboardingVersion": 1,
            "startTimeValue": windowStartValue,
            "bedTimeValue": windowBedValue,
            "nudgeDelivery": "both",
            "snoozeMinutes": 20,
            "isMuted": true,
            "mutedUntil": now.addingTimeInterval(20 * 60),
            "pendingVisualNudgeCount": 1,
            "lastVisualNudgeAt": now.addingTimeInterval(-60),
        ]
    ),
    CaptureState(
        name: "welcome",
        values: [
            "onboardingVersion": 0,
            "nudgeDelivery": "sound",
        ]
    ),
    CaptureState(
        name: "sound",
        values: [
            "onboardingVersion": 1,
            "nudgeDelivery": "sound",
            "selectedSound": "shy",
        ]
    ),
    CaptureState(
        name: "visual",
        values: [
            "onboardingVersion": 1,
            "nudgeDelivery": "visual",
        ]
    ),
    CaptureState(
        name: "both-progressive",
        values: [
            "onboardingVersion": 1,
            "nudgeDelivery": "both",
            "progressive": true,
            "selectedSound": "shy",
        ]
    ),
    CaptureState(
        name: "paused",
        values: [
            "onboardingVersion": 1,
            "startTimeValue": 21 * 3600 + 30 * 60,
            "bedTimeValue": 23 * 3600,
            "nudgeDelivery": "sound",
            "isMuted": true,
            "mutedUntil": nextDefaultWindowEnd,
            "mutedWholeWindow": true,
        ]
    ),
    CaptureState(
        name: "visual-pending",
        values: [
            "onboardingVersion": 1,
            "nudgeDelivery": "visual",
            "pendingVisualNudgeCount": 3,
            "lastVisualNudgeAt": now,
        ]
    ),
]

func sha256(of url: URL) throws -> String {
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func imageDimensions(at url: URL) throws -> [String: Int] {
    guard
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        let width = properties[kCGImagePropertyPixelWidth] as? Int,
        let height = properties[kCGImagePropertyPixelHeight] as? Int
    else {
        throw CaptureError(message: "Could not read image dimensions: \(url.path)")
    }
    return ["width": width, "height": height]
}

func validateImageContent(at url: URL) throws {
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    guard let bitmap = NSBitmapImageRep(data: data) else {
        throw CaptureError(message: "Could not decode image: \(url.path)")
    }
    let sampleCount = 8
    var pixels = [UInt8](repeating: 0, count: sampleCount * sampleCount * 4)
    guard let image = bitmap.cgImage,
        let context = CGContext(
            data: &pixels,
            width: sampleCount,
            height: sampleCount,
            bitsPerComponent: 8,
            bytesPerRow: sampleCount * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else {
        throw CaptureError(message: "Could not normalize image: \(url.path)")
    }
    context.interpolationQuality = .low
    context.draw(image, in: CGRect(x: 0, y: 0, width: sampleCount, height: sampleCount))
    let maximumComponent = stride(from: 0, to: pixels.count, by: 4).reduce(UInt8(0)) {
        max($0, pixels[$1], pixels[$1 + 1], pixels[$1 + 2])
    }
    guard maximumComponent > 2 else {
        throw CaptureError(message: "Captured image is empty or near-black: \(url.path)")
    }
}

func waitForCapture(at directory: URL, process: Process) throws -> [URL] {
    let expected = [
        directory.appendingPathComponent("preferences.png"),
        directory.appendingPathComponent("tonight-popover.png"),
    ]
    // Cold SwiftUI and audio-resource initialization can exceed 12 seconds on
    // a saturated host. Keep the bound finite while allowing the real app to
    // finish its delayed, two-stage native capture.
    let deadline = Date().addingTimeInterval(30)
    while Date() < deadline, process.isRunning {
        if expected.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) {
            // The app writes the optional native-window image before the two required renders.
            let nativeWindow = directory.appendingPathComponent("preferences-window.png")
            return FileManager.default.fileExists(atPath: nativeWindow.path) ? [nativeWindow] + expected : expected
        }
        Thread.sleep(forTimeInterval: 0.2)
    }
    let missing = expected.filter { !FileManager.default.fileExists(atPath: $0.path) }
    let processState =
        process.isRunning
        ? "child was still running at timeout"
        : "child exited with status \(process.terminationStatus) (reason \(process.terminationReason.rawValue))"
    throw CaptureError(
        message:
            "Capture did not complete: \(missing.map(\.lastPathComponent).joined(separator: ", ")); \(processState)"
    )
}

/// A sandboxed build reads its container's preferences, so `defaults import` seeding would be ignored.
func isSandboxed(_ executable: URL) throws -> Bool {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
    process.arguments = ["-d", "--entitlements", "-", "--xml", executable.path]
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    // An unsigned executable, or one signed without entitlements, is not sandboxed.
    guard process.terminationStatus == 0, !data.isEmpty,
        let entitlements = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    else {
        return false
    }
    return entitlements["com.apple.security.app-sandbox"] as? Bool == true
}

func runningCandidateProcessIDs(for executable: URL) -> [pid_t] {
    let expected = executable.resolvingSymlinksInPath().standardizedFileURL
    return NSWorkspace.shared.runningApplications.compactMap { application in
        guard
            let runningExecutable = application.executableURL?
                .resolvingSymlinksInPath()
                .standardizedFileURL,
            runningExecutable == expected
        else {
            return nil
        }
        return application.processIdentifier
    }
}

func terminate(_ process: Process) {
    guard process.isRunning else { return }
    process.terminate()
    let deadline = Date().addingTimeInterval(3)
    while process.isRunning, Date() < deadline {
        Thread.sleep(forTimeInterval: 0.05)
    }
    if process.isRunning {
        kill(process.processIdentifier, SIGKILL)
    }
    process.waitUntilExit()
}

func runDefaults(_ arguments: [String], input: Data? = nil) throws -> String {
    let process = Process()
    let standardInput = Pipe()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
    process.arguments = arguments
    if input != nil {
        process.standardInput = standardInput
    }
    process.standardOutput = output
    process.standardError = output
    try process.run()
    if let input {
        standardInput.fileHandleForWriting.write(input)
        try standardInput.fileHandleForWriting.close()
    }
    process.waitUntilExit()
    let message =
        String(
            data: output.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
    guard process.terminationStatus == 0 else {
        throw CaptureError(
            message:
                "defaults \(arguments.first ?? "command") failed: \(message.trimmingCharacters(in: .whitespacesAndNewlines))"
        )
    }
    return message
}

func seedDefaultsSuite(named suiteName: String, values: [String: Any]) throws {
    let propertyList = try PropertyListSerialization.data(
        fromPropertyList: values,
        format: .xml,
        options: 0
    )
    _ = try runDefaults(["import", suiteName, "-"], input: propertyList)
}

func clearDefaultsSuite(named suiteName: String) throws {
    let prefix = "BeddyButler.AcceptanceCapture."
    guard suiteName.hasPrefix(prefix),
        UUID(uuidString: String(suiteName.dropFirst(prefix.count))) != nil
    else {
        throw CaptureError(message: "Refusing to clear an unexpected defaults domain")
    }
    _ = try runDefaults(["delete", suiteName])
    Thread.sleep(forTimeInterval: 0.2)
    let preferenceFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Preferences", isDirectory: true)
        .appendingPathComponent("\(suiteName).plist")
    if FileManager.default.fileExists(atPath: preferenceFile.path) {
        // The child is terminated before cleanup, and the UUID-qualified suite
        // belongs solely to this capture. Remove any cfprefsd file left behind
        // by the domain deletion, including values seeded for the capture.
        try FileManager.default.removeItem(at: preferenceFile)
    }
}

do {
    if try isSandboxed(executable) {
        fputs(
            "The candidate is sandboxed, so it would ignore the seeded defaults. Capture an unsigned build (CODE_SIGNING_ALLOWED=NO) instead.\n",
            stderr
        )
        exit(78)
    }
    let existingProcessIDs = runningCandidateProcessIDs(for: executable)
    guard existingProcessIDs.isEmpty else {
        throw CaptureError(
            message:
                "The exact candidate executable is already running as PID(s) \(existingProcessIDs.map(String.init).joined(separator: ", ")); close that instance before capture"
        )
    }
    if FileManager.default.fileExists(atPath: outputDirectory.path) {
        throw CaptureError(
            message: "Output directory already exists; choose a new path: \(outputDirectory.path)"
        )
    }
    try FileManager.default.createDirectory(
        at: outputDirectory,
        withIntermediateDirectories: true
    )

    var captureRecords: [[String: Any]] = []
    var imageHashes: [String: [String]] = [:]
    for state in states {
        let unexpectedProcessIDs = runningCandidateProcessIDs(for: executable)
        guard unexpectedProcessIDs.isEmpty else {
            throw CaptureError(
                message:
                    "The exact candidate executable remained registered as PID(s) \(unexpectedProcessIDs.map(String.init).joined(separator: ", ")) before state \(state.name)"
            )
        }
        let suiteName = "BeddyButler.AcceptanceCapture.\(UUID().uuidString)"
        try seedDefaultsSuite(named: suiteName, values: state.values)

        let stateDirectory = outputDirectory.appendingPathComponent(
            state.name,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: stateDirectory,
            withIntermediateDirectories: true
        )

        let process = Process()
        process.executableURL = executable
        process.environment = ProcessInfo.processInfo.environment.merging(
            [
                "BEDDY_BUTLER_CAPTURE_UI_DIR": stateDirectory.path,
                "BEDDY_BUTLER_DEFAULTS_SUITE": suiteName,
                "BEDDY_BUTLER_OPEN_PREFERENCES": "1",
            ],
            uniquingKeysWith: { _, requested in requested }
        )
        let log = Pipe()
        process.standardOutput = log
        process.standardError = log

        do {
            try process.run()
            let images = try waitForCapture(at: stateDirectory, process: process)
            terminate(process)
            let processOutput = log.fileHandleForReading.readDataToEndOfFile()
            if let text = String(data: processOutput, encoding: .utf8), !text.isEmpty {
                try text.write(
                    to: stateDirectory.appendingPathComponent("app.log"),
                    atomically: true,
                    encoding: .utf8
                )
            }

            var imageRecords: [[String: Any]] = []
            for image in images {
                try validateImageContent(at: image)
                let digest = try sha256(of: image)
                imageHashes[image.lastPathComponent, default: []].append(digest)
                imageRecords.append([
                    "file": image.path.replacingOccurrences(
                        of: outputDirectory.path + "/",
                        with: ""
                    ),
                    "sha256": digest,
                    "pixels": try imageDimensions(at: image),
                ])
            }
            captureRecords.append([
                "state": state.name,
                "seeded_values": state.values.mapValues { String(describing: $0) },
                "images": imageRecords,
            ])
            print("Captured \(state.name)")
        } catch {
            terminate(process)
            let processOutput = log.fileHandleForReading.readDataToEndOfFile()
            if let text = String(data: processOutput, encoding: .utf8), !text.isEmpty {
                fputs(text, stderr)
                try? text.write(
                    to: stateDirectory.appendingPathComponent("app.log"),
                    atomically: true,
                    encoding: .utf8
                )
            }
            try? clearDefaultsSuite(named: suiteName)
            throw error
        }
        try clearDefaultsSuite(named: suiteName)
    }

    let preferenceVariants = Set(imageHashes["preferences.png", default: []]).count
    let popoverVariants = Set(imageHashes["tonight-popover.png", default: []]).count
    guard preferenceVariants >= 3 else {
        throw CaptureError(
            message:
                "Preferences captures lack state diversity: expected at least 3 distinct images, found \(preferenceVariants)"
        )
    }
    guard popoverVariants >= 5 else {
        throw CaptureError(
            message:
                "Tonight popover captures lack state diversity: expected at least 5 distinct images, found \(popoverVariants)"
        )
    }

    let manifest: [String: Any] = [
        "schema_version": 2,
        "captured_at": ISO8601DateFormatter().string(from: Date()),
        "candidate_executable": executable.path,
        "candidate_executable_sha256": try sha256(of: executable),
        "capture_scope": [
            "preferences": [
                "evidence_kind": "structural full-form render",
                "known_limitation":
                    "AppKit-backed controls may show unavailable placeholder tiles in offscreen rendering.",
                "native_window_person_review_required": true,
            ],
            "tonight_popover": [
                "evidence_kind": "faithful production SwiftUI render",
                "person_visual_review_required": true,
            ],
        ],
        "publication_authority": false,
        "captures": captureRecords,
    ]
    let manifestData = try JSONSerialization.data(
        withJSONObject: manifest,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    )
    try manifestData.write(
        to: outputDirectory.appendingPathComponent("manifest.json"),
        options: .atomic
    )
    let imageCount = captureRecords.reduce(0) { $0 + (($1["images"] as? [[String: Any]])?.count ?? 0) }
    print(
        "SwiftUI state captures completed (native controls require separate window screenshots): \(states.count) states, \(imageCount) images"
    )
} catch {
    fputs("Acceptance-state capture failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
