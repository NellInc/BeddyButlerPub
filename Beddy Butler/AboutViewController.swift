import AppKit
import Foundation
import SwiftUI

enum ApplicationMetadata {
    static let creditLine = "Design and engineering by Nell Watson and David Garces."
    static let qaCreditLine = "QA by Filip Alimpić"
    static let copyrightLine = "© 2015–2026 Nell Watson Inc."

    static var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Beddy Butler"
    }

    static var versionDescription: String {
        "Version \(shortVersion) · Build \(buildNumber)"
    }

    static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "Unknown"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "Unknown"
    }
}

@MainActor
struct AboutBeddyButlerView: View {
    var body: some View {
        ZStack {
            BeddyBackdrop()

            VStack(spacing: 0) {
                Image("AboutIcon")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 154, height: 154)
                    .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                    .accessibilityLabel("Beddy Butler yawning beside a crescent moon")
                    .accessibilityIdentifier("about.icon")

                Text(ApplicationMetadata.displayName)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .tracking(-0.7)
                    .foregroundStyle(BeddyPalette.ink)
                    .padding(.top, 24)
                    .accessibilityIdentifier("about.title")

                Text("A gracious last call for the evening.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(BeddyPalette.blueBright)
                    .padding(.top, 5)

                Text(ApplicationMetadata.versionDescription)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(BeddyPalette.muted)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(BeddyPalette.glass, in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(BeddyPalette.line, lineWidth: 1)
                    }
                    .padding(.top, 15)

                Text(
                    "Beddy Butler waits quietly in your menu bar, then offers a gentle, persistent, occasionally theatrical reminder that tomorrow deserves a rested you."
                )
                .font(.system(size: 14))
                .foregroundStyle(BeddyPalette.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 24)

                Text(ApplicationMetadata.creditLine)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BeddyPalette.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)
                    .accessibilityIdentifier("about.credit")

                Text(ApplicationMetadata.qaCreditLine)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(BeddyPalette.muted)
                    .padding(.top, 5)
                    .accessibilityIdentifier("about.qa-credit")

                HStack(spacing: 12) {
                    if let website = ExternalLinks.website {
                        Link(destination: website) {
                            Label("Visit website", systemImage: "safari")
                                .frame(minWidth: 116)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(BeddyPalette.blue)
                        .accessibilityIdentifier("about.website")
                    }

                    if let source = URL(string: "https://github.com/NellInc/beddybutlerpub") {
                        Link(destination: source) {
                            Label("View source", systemImage: "chevron.left.forwardslash.chevron.right")
                                .frame(minWidth: 116)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("about.source")
                    }
                }
                .padding(.top, 25)

                Text(ApplicationMetadata.copyrightLine)
                    .font(.system(size: 10))
                    .foregroundStyle(BeddyPalette.faint)
                    .padding(.top, 23)
            }
            .frame(maxWidth: 410)
            .padding(.horizontal, 48)
            .padding(.vertical, 40)
        }
        .frame(width: 520, height: 650)
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("About Beddy Butler")
    }
}

@MainActor
final class AboutWindowController: NSWindowController {
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 650),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "About Beddy Butler"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.contentViewController = NSHostingController(rootView: AboutBeddyButlerView())
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
