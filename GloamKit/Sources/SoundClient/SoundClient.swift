import Assets
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
    public var playWelcome: @Sendable () async -> Void = {}
    public var playRefineStarted: @Sendable () async -> Void = {}
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
            },
            playWelcome: {
                await runtime.play(.welcome)
            },
            playRefineStarted: {
                await runtime.play(.refineStarted)
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
        case welcome
        case refineStarted

        var variants: [SoundLibrary] {
            switch self {
            case .recordingStarted: [.start1, .start2, .start3, .start4]
            case .transcriptionStarted: [.prestop]
            case .transcriptionCompleted: [.stop1, .stop2, .stop3, .stop4]
            case .transcriptionNoResult: [.noresult1, .noresult2, .noresult3, .noresult4]
            case .welcome: [.welcome]
            case .refineStarted: [.refine]
            }
        }

        var volume: Float {
            switch self {
            case .recordingStarted: 0.3
            case .transcriptionStarted: 0.2
            case .transcriptionCompleted: 0.25
            case .transcriptionNoResult: 0.2
            case .welcome: 0.3
            case .refineStarted: 0.25
            }
        }
    }

    private var players: [SoundLibrary: AVAudioPlayer] = [:]

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

    private func player(for sound: SoundLibrary) throws -> AVAudioPlayer {
        if let existing = players[sound] {
            return existing
        }
        guard let url = sound.url else {
            throw NSError(
                domain: "SoundClient",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing sound resource \(sound.rawValue).m4a"]
            )
        }
        let player = try AVAudioPlayer(contentsOf: url)
        player.prepareToPlay()
        players[sound] = player
        return player
    }
}
