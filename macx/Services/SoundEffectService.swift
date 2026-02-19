import AVFoundation
import Foundation
import os

@MainActor
final class SoundEffectService {
    enum Effect: String {
        case recordingStarted = "click"
        case transcriptionStarted = "magic-transition"
        case transcriptionCompleted = "jingle"

        var volume: Float {
            switch self {
            case .recordingStarted:
                return 0.3
            case .transcriptionStarted:
                return 0.2
            case .transcriptionCompleted:
                return 0.25
            }
        }
    }

    private var players: [Effect: AVAudioPlayer] = [:]
    private let logger = Logger(subsystem: "com.optimalapps.macx", category: "SoundEffectService")

    func play(_ effect: Effect) {
        do {
            let player = try player(for: effect)
            player.volume = effect.volume
            player.currentTime = 0
            player.play()
        } catch {
            logger.error("Failed to play \(effect.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func player(for effect: Effect) throws -> AVAudioPlayer {
        if let existing = players[effect] {
            return existing
        }

        guard let url = resourceURL(for: effect) else {
            throw NSError(
                domain: "SoundEffectService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing sound resource \(effect.rawValue).mp3"]
            )
        }

        let player = try AVAudioPlayer(contentsOf: url)
        player.prepareToPlay()
        players[effect] = player
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
