import AVFoundation
import Foundation

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

    var assetName: String { "\(title)Icon" }

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
        case .playbackRefused(let url):
            "macOS could not start \(url.lastPathComponent)."
        case .playbackFailed(let url, let error):
            "Could not play \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }
}

@MainActor
protocol AudioPlaying: AnyObject {
    @discardableResult
    func play(_ personality: ButlerPersonality, volume: Double) throws -> URL
}

@MainActor
final class AudioPlayer: AudioPlaying {
    private let library: AudioLibrary
    private var player: AVAudioPlayer?
    private var clipSelector = AudioClipSelector()

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
            nextPlayer.volume = Float(min(max(volume, 0), 1))
            guard nextPlayer.prepareToPlay(), nextPlayer.play() else {
                throw AudioPlayerError.playbackRefused(clip)
            }
            player = nextPlayer
            return clip
        } catch let error as AudioPlayerError {
            throw error
        } catch {
            throw AudioPlayerError.playbackFailed(clip, error)
        }
    }
}
