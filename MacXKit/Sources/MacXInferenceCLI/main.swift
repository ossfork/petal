import Foundation
import MacXMLXClient
import MacXShared

@main
struct MacXInferenceCLI {
    static func main() async {
        do {
            let options = try CLIOptions.parse(CommandLine.arguments)
            let client = MacXMLXClient.liveValue

            guard FileManager.default.fileExists(atPath: options.audioURL.path) else {
                throw CLIError("Audio file not found at \(options.audioURL.path)")
            }

            let modelInfo = options.model.modelInfo
            if !client.isModelDownloaded(modelInfo) {
                if options.downloadIfNeeded {
                    print("Downloading model \(options.model.rawValue)...")
                    try await client.downloadModel(modelInfo) { fraction, status in
                        let percent = Int((fraction * 100).rounded())
                        print("[download \(percent)%] \(status)")
                    }
                } else {
                    throw CLIError("Model \(options.model.rawValue) is not downloaded. Use --download-if-needed.")
                }
            }

            print("Preparing model \(options.model.rawValue)...")
            try await client.prepareModelIfNeeded(options.model.pipelineModel)

            let start = Date()
            let transcript = try await client.transcribe(
                options.audioURL,
                options.mode == .verbatim
                    ? .verbatim
                    : .smart(prompt: options.prompt ?? Self.defaultSmartPrompt)
            )
            let elapsed = Date().timeIntervalSince(start)
            await client.unloadModel()

            print("=== TRANSCRIPT BEGIN ===")
            print(transcript)
            print("=== TRANSCRIPT END ===")
            print("ElapsedSeconds=\(elapsed.formatted(.number.precision(.fractionLength(2))))")
        } catch {
            fputs("MacXInferenceCLI error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

private struct CLIOptions {
    enum Mode: String {
        case verbatim
        case smart
    }

    let audioURL: URL
    let model: MacXModelOption
    let mode: Mode
    let prompt: String?
    let downloadIfNeeded: Bool

    static func parse(_ argv: [String]) throws -> Self {
        var audioPath: String?
        var model: MacXModelOption = .defaultOption
        var mode: Mode = .verbatim
        var prompt: String?
        var downloadIfNeeded = false

        var index = 1
        while index < argv.count {
            let arg = argv[index]
            switch arg {
            case "--audio":
                index += 1
                guard index < argv.count else { throw CLIError("--audio requires a path") }
                audioPath = argv[index]
            case "--model":
                index += 1
                guard index < argv.count else { throw CLIError("--model requires a value") }
                guard let parsed = MacXModelOption(rawValue: argv[index]) else {
                    throw CLIError("Invalid --model value: \(argv[index])")
                }
                model = parsed
            case "--mode":
                index += 1
                guard index < argv.count else { throw CLIError("--mode requires a value") }
                guard let parsed = Mode(rawValue: argv[index]) else {
                    throw CLIError("Invalid --mode value: \(argv[index])")
                }
                mode = parsed
            case "--prompt":
                index += 1
                guard index < argv.count else { throw CLIError("--prompt requires a value") }
                prompt = argv[index]
            case "--download-if-needed":
                downloadIfNeeded = true
            case "--help", "-h":
                printUsageAndExit()
            default:
                throw CLIError("Unknown argument: \(arg)")
            }
            index += 1
        }

        guard let audioPath else {
            throw CLIError("--audio is required")
        }

        return Self(
            audioURL: URL(fileURLWithPath: audioPath),
            model: model,
            mode: mode,
            prompt: prompt,
            downloadIfNeeded: downloadIfNeeded
        )
    }
}

private struct CLIError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

private func printUsageAndExit() -> Never {
    print(
        """
        Usage:
          swift run --package-path MacXKit MacXInferenceCLI --audio <path> [--model mini-3b|mini-3b-8bit|mini-3b-4bit] [--mode verbatim|smart] [--prompt <text>] [--download-if-needed]
        """
    )
    exit(0)
}

private extension MacXInferenceCLI {
    static let defaultSmartPrompt = "Clean up filler words and repeated phrases. Return a polished version of what was said."
}

private extension MacXModelOption {
    var modelInfo: MacXMLXModelInfo {
        let descriptor = descriptor
        return MacXMLXModelInfo(
            id: descriptor.id,
            repoId: descriptor.repoID,
            name: descriptor.name,
            summary: descriptor.summary,
            size: descriptor.size,
            quantization: descriptor.quantization,
            parameters: descriptor.parameters,
            recommended: descriptor.recommended
        )
    }

    var pipelineModel: MacXMLXPipelineModel {
        switch self {
        case .mini3b:
            return .mini3b
        case .mini3b8bit:
            return .mini3b8bit
        case .mini3b4bit:
            return .mini3b4bit
        }
    }
}
