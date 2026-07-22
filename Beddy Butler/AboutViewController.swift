import AppKit
import Foundation

enum ApplicationMetadata {
    static var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Beddy Butler"
    }

    static var versionDescription: String {
        "Version \(shortVersion) (\(buildNumber))"
    }

    static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "Unknown"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "Unknown"
    }

    static var aboutOptions: [NSApplication.AboutPanelOptionKey: Any] {
        [
            .applicationName: displayName,
            .applicationVersion: versionDescription,
            .credits: NSAttributedString(
                string:
                    "A playful bedtime nudge from Nell Watson.\nRevived for modern macOS in 2026.\n\nCopyright © 2015-2026 Nell Watson Inc."
            ),
        ]
    }
}
