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
    public var playTranscriptionNoResult: @Sendable () async -> Void = {}
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
            },
            playTranscriptionNoResult: {
                await runtime.play(.transcriptionNoResult)
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
    enum Effect {
        case recordingStarted
        case transcriptionStarted
        case transcriptionCompleted
        case transcriptionNoResult

        var variants: [String] {
            switch self {
            case .recordingStarted: return ["start1", "start2", "start3", "start4"]
            case .transcriptionStarted: return ["prestop"]
            case .transcriptionCompleted: return ["stop1", "stop2", "stop3", "stop4"]
            case .transcriptionNoResult: return ["noresult1", "noresult2", "noresult3", "noresult4"]
            }
        }

        var volume: Float {
            switch self {
            case .recordingStarted: return 0.3
            case .transcriptionStarted: return 0.2
            case .transcriptionCompleted: return 0.25
            case .transcriptionNoResult: return 0.2
            }
        }
    }

    private var players: [String: AVAudioPlayer] = [:]

    func play(_ effect: Effect) {
        let variants = effect.variants
        let variant = variants[Int.random(in: 0..<variants.count)]
        do {
            let player = try player(for: variant)
            player.volume = effect.volume
            player.currentTime = 0
            player.play()
        } catch {}
    }

    private func player(for variant: String) throws -> AVAudioPlayer {
        if let existing = players[variant] {
            return existing
        }
        guard let url = resourceURL(for: variant) else {
            throw NSError(
                domain: "SoundClient",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing sound resource \(variant).m4a"]
            )
        }
        let player = try AVAudioPlayer(contentsOf: url)
        player.prepareToPlay()
        players[variant] = player
        return player
    }

    private func resourceURL(for variant: String) -> URL? {
        if let subdirectoryURL = Bundle.main.url(
            forResource: variant,
            withExtension: "m4a",
            subdirectory: "SoundEffects"
        ) {
            return subdirectoryURL
        }
        return Bundle.main.url(forResource: variant, withExtension: "m4a")
    }
}
