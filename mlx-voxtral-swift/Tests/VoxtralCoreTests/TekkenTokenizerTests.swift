import Foundation
import XCTest
@testable import VoxtralCore

final class TekkenTokenizerTests: XCTestCase {
    func testDecodeMergesByteFragmentsIntoUTF8Text() throws {
        let modelDir = try makeTokenizerFixture(
            specialTokens: [
                (1, "<s>"),
                (2, "</s>"),
                (3, "[INST]"),
                (4, "[/INST]"),
                (11, "<pad>"),
                (24, "[AUDIO]"),
                (25, "[BEGIN_AUDIO]"),
                (34, "[TRANSCRIBE]"),
            ],
            vocab: [
                (0, [0xC3], nil), // first byte of "é"
                (1, [0xA9], nil), // second byte of "é"
            ]
        )

        defer { try? FileManager.default.removeItem(at: modelDir) }

        let tokenizer = TekkenTokenizer(modelPath: modelDir.path)
        let decoded = tokenizer.decode([1, 1000, 1001], skipSpecialTokens: true)

        XCTAssertEqual(decoded, "é")
    }

    func testGetControlTokenUsesSpecialTokenTableFromTekken() throws {
        let modelDir = try makeTokenizerFixture(
            specialTokens: [
                (101, "<s>"),
                (102, "</s>"),
                (142, "[INST]"),
                (143, "[/INST]"),
                (151, "<pad>"),
                (224, "[AUDIO]"),
                (225, "[BEGIN_AUDIO]"),
                (234, "[TRANSCRIBE]"),
            ],
            vocab: [
                (0, [0x61], "a"),
                (1, [0x62], "b"),
            ],
            generationConfig: [
                "bos_token_id": 101,
                "eos_token_id": 102,
                "pad_token_id": 151,
            ],
            modelConfig: [
                "audio_token_id": 224,
            ]
        )

        defer { try? FileManager.default.removeItem(at: modelDir) }

        let tokenizer = TekkenTokenizer(modelPath: modelDir.path)

        XCTAssertEqual(tokenizer.getControlToken("[INST]"), 142)
        XCTAssertEqual(tokenizer.getControlToken("[/INST]"), 143)
        XCTAssertEqual(tokenizer.getControlToken("[BEGIN_AUDIO]"), 225)
        XCTAssertEqual(tokenizer.getControlToken("[TRANSCRIBE]"), 234)
    }
}

private func makeTokenizerFixture(
    specialTokens: [(Int, String)],
    vocab: [(Int, [UInt8], String?)],
    generationConfig: [String: Any] = [
        "bos_token_id": 1,
        "eos_token_id": 2,
        "pad_token_id": 11,
    ],
    modelConfig: [String: Any] = [
        "audio_token_id": 24,
    ]
) throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let tekkenJSON: [String: Any] = [
        "config": [
            "pattern": ".+?",
            "num_vocab_tokens": 150000,
            "default_vocab_size": 1002,
            "default_num_special_tokens": 1000,
            "version": "test",
        ],
        "vocab": vocab.map { rank, bytes, tokenString in
            [
                "rank": rank,
                "token_bytes": Data(bytes).base64EncodedString(),
                "token_str": tokenString as Any,
            ]
        },
        "special_tokens": specialTokens.map { rank, tokenString in
            [
                "rank": rank,
                "token_str": tokenString,
                "is_control": true,
            ]
        },
    ]

    try JSONSerialization.data(withJSONObject: tekkenJSON, options: [.prettyPrinted])
        .write(to: tempDir.appendingPathComponent("tekken.json"))
    try JSONSerialization.data(withJSONObject: generationConfig, options: [.prettyPrinted])
        .write(to: tempDir.appendingPathComponent("generation_config.json"))
    try JSONSerialization.data(withJSONObject: modelConfig, options: [.prettyPrinted])
        .write(to: tempDir.appendingPathComponent("config.json"))

    return tempDir
}
