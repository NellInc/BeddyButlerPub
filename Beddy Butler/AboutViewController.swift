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
                    "An original bedtime companion.\n\nDesigned and engineered by Nell Watson and David Garces.\n\nCopyright © 2015-2026 Nell Watson Inc."
            ),
        ]
    }
}
