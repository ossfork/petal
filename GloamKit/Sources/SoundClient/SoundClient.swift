import AVFoundation
import Dependencies
import DependenciesMacros
import Foundation
import Shared

@DependencyClient
public struct SoundClient: Sendable {
    public var playRecordingStarted: @Sendable () async -> Void = {}
    public var playTranscriptionStarted: @Sendable () async -> Void = {}
    public var playTranscriptionCompleted: @Sendable () async -> Void = {}
}

extension SoundClient: DependencyKey {
    public static var liveValue: Self {
        let runtime = SoundRuntime()
        return Self(
            playRecordingStarted: {
                await runtime.play(.recordingStarted)
            },
            playTranscriptionStarted: {
                await runtime.play(.transcriptionStarted)
            },
            playTranscriptionCompleted: {
                await runtime.play(.transcriptionCompleted)
            }
        )
    }
}

extension SoundClient: TestDependencyKey {
    public static var testValue: Self {
        Self()
    }
}

public extension DependencyValues {
    var soundClient: SoundClient {
        get { self[SoundClient.self] }
        set { self[SoundClient.self] = newValue }
    }
}

private actor SoundRuntime {
    enum Effect: String {
        case recordingStarted = "click"
        case transcriptionStarted = "magic-transition"
        case transcriptionCompleted = "jingle"

        var volume: Float {
            switch self {
            case .recordingStarted: return 0.3
            case .transcriptionStarted: return 0.2
            case .transcriptionCompleted: return 0.25
            }
        }
    }

    private var players: [Effect.RawValue: AVAudioPlayer] = [:]

    func play(_ effect: Effect) {
        do {
            let player = try player(for: effect)
            player.volume = effect.volume
            player.currentTime = 0
            player.play()
        } catch {}
    }

    private func player(for effect: Effect) throws -> AVAudioPlayer {
        if let existing = players[effect.rawValue] {
            return existing
        }
        guard let url = resourceURL(for: effect) else {
            throw NSError(
                domain: "SoundClient",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing sound resource \(effect.rawValue).mp3"]
            )
        }
        let player = try AVAudioPlayer(contentsOf: url)
        player.prepareToPlay()
        players[effect.rawValue] = player
        return player
    }

    private func resourceURL(for effect: Effect) -> URL? {
        if let subdirectoryURL = Bundle.main.url(
            forResource: effect.rawValue,
            withExtension: "mp3",
            subdirectory: "SoundEffects"
        ) {
            return subdirectoryURL
        }
        return Bundle.main.url(forResource: effect.rawValue, withExtension: "mp3")
    }
}
