import AVFoundation
import Foundation
import OSLog

enum ButlerPersonality: String, CaseIterable, Identifiable, Codable, Sendable {
    case shy
    case insistent
    case zombie

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shy: "Shy"
        case .insistent: "Insistent"
        case .zombie: "Zombie"
        }
    }

    var rigAssetName: String { "\(title)Rig" }
    var indefiniteArticle: String { self == .insistent ? "an" : "a" }
    var sampleLabel: String { "Hear \(indefiniteArticle) \(title) Sample" }

    var guidance: String {
        switch self {
        case .shy:
            "A discreet reminder from across the room."
        case .insistent:
            "A firmer prompt when subtle hints are too easy to ignore."
        case .zombie:
            "The theatrical last resort for determined night owls."
        }
    }

    func capped(at maximum: ButlerPersonality) -> ButlerPersonality {
        let order: [ButlerPersonality] = [.shy, .insistent, .zombie]
        return order[min(order.firstIndex(of: self) ?? 0, order.firstIndex(of: maximum) ?? 0)]
    }

    var escalated: ButlerPersonality {
        switch self {
        case .shy: .insistent
        case .insistent, .zombie: .zombie
        }
    }

    init(storedValue: String?) {
        guard let storedValue else {
            self = .shy
            return
        }

        self =
            Self.allCases.first {
                $0.rawValue.caseInsensitiveCompare(storedValue) == .orderedSame
                    || $0.title.caseInsensitiveCompare(storedValue) == .orderedSame
            } ?? .shy
    }
}

struct AudioLibrary {
    let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func clips(for personality: ButlerPersonality) -> [URL] {
        let allClips = bundle.urls(forResourcesWithExtension: "mp3", subdirectory: nil) ?? []
        return Self.clips(for: personality, among: allClips)
    }

    static func clips(for personality: ButlerPersonality, among urls: [URL]) -> [URL] {
        urls
            .filter { $0.lastPathComponent.localizedCaseInsensitiveContains(personality.title) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}

struct AudioClipSelector {
    private var remaining: [ButlerPersonality: [URL]] = [:]
    private var lastSelected: [ButlerPersonality: URL] = [:]

    mutating func next(
        for personality: ButlerPersonality,
        from clips: [URL],
        shuffle: ([URL]) -> [URL] = { $0.shuffled() }
    ) -> URL? {
        guard !clips.isEmpty else { return nil }

        var queue = remaining[personality] ?? []
        let available = Set(clips)
        queue.removeAll { !available.contains($0) }

        if queue.isEmpty {
            queue = shuffle(clips)
            if queue.count > 1, queue.first == lastSelected[personality] {
                queue.swapAt(0, 1)
            }
        }

        let selected = queue.removeFirst()
        remaining[personality] = queue
        lastSelected[personality] = selected
        return selected
    }
}

enum AudioPlayerError: LocalizedError {
    case noClips(ButlerPersonality)
    case playbackRefused(URL)
    case playbackFailed(URL, Error)

    var errorDescription: String? {
        switch self {
        case .noClips(let personality):
            "No \(personality.title) voice clips were found in the app bundle."
        case .playbackRefused:
            "macOS could not start the voice clip."
        case .playbackFailed(_, let error):
            "Could not play the voice clip: \(error.localizedDescription)"
        }
    }
}

@MainActor
protocol AudioPlaying: AnyObject {
    @discardableResult
    func play(_ personality: ButlerPersonality, volume: Double) throws -> URL
    /// Fades out and stops any clip that is still playing.
    func stop()
}

@MainActor
final class AudioPlayer: AudioPlaying {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "BeddyButler",
        category: "audio"
    )
    private let library: AudioLibrary
    private var player: AVAudioPlayer?
    private var clipSelector = AudioClipSelector()
    private static let fadeOutDuration: TimeInterval = 0.2

    init(library: AudioLibrary = AudioLibrary()) {
        self.library = library
    }

    @discardableResult
    func play(_ personality: ButlerPersonality, volume: Double = 1) throws -> URL {
        guard let clip = clipSelector.next(for: personality, from: library.clips(for: personality)) else {
            throw AudioPlayerError.noClips(personality)
        }

        do {
            let nextPlayer = try AVAudioPlayer(contentsOf: clip)
            nextPlayer.volume = Self.amplitude(forSliderPosition: volume)
            guard nextPlayer.prepareToPlay(), nextPlayer.play() else {
                throw AudioPlayerError.playbackRefused(clip)
            }
            player = nextPlayer
            return clip
        } catch let error as AudioPlayerError {
            logger.error("Could not play \(clip.lastPathComponent, privacy: .public)")
            throw error
        } catch {
            logger.error(
                "Could not play \(clip.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            throw AudioPlayerError.playbackFailed(clip, error)
        }
    }

    func stop() {
        guard let fading = player else { return }
        player = nil
        guard fading.isPlaying else { return }
        fading.setVolume(0, fadeDuration: Self.fadeOutDuration)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.fadeOutDuration))
            fading.stop()
        }
    }

    /// Maps the linear volume slider to a squared amplitude so quiet settings stay usable.
    static func amplitude(forSliderPosition volume: Double) -> Float {
        let finiteVolume = volume.isFinite ? volume : AppSettings.defaultVoiceVolume
        let position = min(max(finiteVolume, 0), 1)
        return Float(position * position)
    }
}
