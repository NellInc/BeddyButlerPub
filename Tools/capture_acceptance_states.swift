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

let now = Date()
let states = [
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
            "nudgeDelivery": "sound",
            "isMuted": true,
            "mutedUntil": now.addingTimeInterval(2 * 60 * 60),
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
            return expected
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
    print("Acceptance-state captures passed: \(states.count) states, \(states.count * 2) images")
} catch {
    fputs("Acceptance-state capture failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
