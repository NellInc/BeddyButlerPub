import AVFoundation
import Foundation
import XCTest

@testable import Beddy_Butler

final class BeddyButlerAudioTests: XCTestCase {
    func testPersonalityMigratesCaseInsensitively() {
        XCTAssertEqual(ButlerPersonality(storedValue: "shy"), .shy)
        XCTAssertEqual(ButlerPersonality(storedValue: "INSISTENT"), .insistent)
        XCTAssertEqual(ButlerPersonality(storedValue: "Zombie"), .zombie)
        XCTAssertEqual(ButlerPersonality(storedValue: "unknown"), .shy)
    }

    func testPersonalityEscalationCapsAtZombie() {
        XCTAssertEqual(ButlerPersonality.shy.escalated, .insistent)
        XCTAssertEqual(ButlerPersonality.insistent.escalated, .zombie)
        XCTAssertEqual(ButlerPersonality.zombie.escalated, .zombie)
    }

    func testStablePersonalityIdentifiersRemainSeparateFromDisplayTitles() {
        XCTAssertEqual(ButlerPersonality.zombie.rawValue, "zombie")
        XCTAssertEqual(ButlerPersonality.zombie.title, "Zombie")
    }

    func testSampleLabelsUseTheCorrectIndefiniteArticle() {
        XCTAssertEqual(ButlerPersonality.shy.sampleLabel, "Hear a Shy Sample")
        XCTAssertEqual(ButlerPersonality.insistent.sampleLabel, "Hear an Insistent Sample")
        XCTAssertEqual(ButlerPersonality.zombie.sampleLabel, "Hear a Zombie Sample")
    }

    func testClipSelectorUsesEveryClipBeforeRepeating() throws {
        let clips = [
            URL(fileURLWithPath: "/tmp/one.mp3"),
            URL(fileURLWithPath: "/tmp/two.mp3"),
            URL(fileURLWithPath: "/tmp/three.mp3"),
        ]
        var selector = AudioClipSelector()
        var selected: [URL] = []

        for _ in clips {
            selected.append(
                try XCTUnwrap(selector.next(for: .shy, from: clips, shuffle: { $0 }))
            )
        }

        XCTAssertEqual(Set(selected), Set(clips))
        XCTAssertNotEqual(
            selected.last,
            selector.next(for: .shy, from: clips, shuffle: { $0 })
        )
    }

    func testLibraryCategorizesClipsByPersonality() {
        let clips = [
            URL(fileURLWithPath: "/tmp/Nell - Shy.01.mp3"),
            URL(fileURLWithPath: "/tmp/Nell - Insistent.01.mp3"),
            URL(fileURLWithPath: "/tmp/Nell - Zombie.01.mp3"),
            URL(fileURLWithPath: "/tmp/readme.txt"),
        ]

        XCTAssertEqual(AudioLibrary.clips(for: .shy, among: clips).count, 1)
        XCTAssertEqual(AudioLibrary.clips(for: .insistent, among: clips).count, 1)
        XCTAssertEqual(AudioLibrary.clips(for: .zombie, among: clips).count, 1)
    }

    func testAllBundledVoiceSetsAreAvailable() {
        let library = AudioLibrary(bundle: .main)

        XCTAssertEqual(library.clips(for: .shy).count, 18)
        XCTAssertEqual(library.clips(for: .insistent).count, 19)
        XCTAssertEqual(library.clips(for: .zombie).count, 66)
    }

    func testBundledZombieClipsAreBriefAndDecodable() throws {
        let clips = AudioLibrary(bundle: .main).clips(for: .zombie)

        XCTAssertFalse(clips.isEmpty)
        for clip in clips {
            let player = try AVAudioPlayer(contentsOf: clip)
            XCTAssertLessThanOrEqual(
                player.duration,
                10,
                "\(clip.lastPathComponent) is too long for a bedtime nudge"
            )
        }
    }
}
