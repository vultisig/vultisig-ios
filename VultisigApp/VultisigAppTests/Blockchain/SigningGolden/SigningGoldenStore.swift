//
//  SigningGoldenStore.swift
//  VultisigAppTests
//
//  Committed golden store + env-gated record mode for the signing-pipeline
//  golden-vector harness. Mirrors the record-flag pattern used by the
//  FigmaParity harness (`ProcessInfo.processInfo.environment[...]` + a
//  `#filePath`-anchored on-disk location), but the goldens here are COMMITTED
//  (not gitignored): the whole point is that a byte drift in the signing
//  pipeline fails CI, so the reference values must travel with the repo.
//
//  Record mode
//  -----------
//  Set `RECORD_SIGNING_GOLDENS=1` in the test environment to regenerate the
//  committed JSON from the current signing code, e.g.:
//
//    RECORD_SIGNING_GOLDENS=1 xcodebuild test \
//      -scheme VultisigApp -destination '<sim>' \
//      -only-testing:VultisigAppTests/SigningGoldenTests
//
//  Regenerate ONLY when a signing-code change is intended to alter the signed
//  bytes; review the JSON diff exactly as you would review the code change,
//  and never record blindly to make a red test go green.
//

import Foundation

/// One committed golden record for a single signing vector. Every field is a
/// stable string (hex / base64 / hash) so the JSON diff is human-reviewable
/// and the comparison is exact.
struct SigningGolden: Codable, Equatable {
    /// The bytes that get signed — `getPreSignedImageHash(...)`, hex, in order.
    let imageHashes: [String]
    /// The signed transaction the broadcast layer would submit
    /// (`getSignedTransaction(...).rawTransaction`).
    let rawTransaction: String
    /// The deterministic transaction hash/id.
    let transactionHash: String
    /// Present for chains that carry a detached signature (e.g. Sui wallet-
    /// standard signature); nil otherwise.
    var signature: String?
    /// Populated only for the ERC20 approve+swap vector (`.regularWithApprove`).
    var approveRawTransaction: String?
    var approveTransactionHash: String?
}

/// Loads / persists the committed golden JSON and exposes the record-mode flag.
/// Paths are anchored at THIS source file (`#filePath`) so the harness resolves
/// the single committed JSON regardless of the calling test's location — the
/// same anchoring trick the FigmaParity harness uses. `#filePath` is baked at
/// compile time and the simulator shares the host filesystem, so read/write of
/// the source-tree JSON works at test runtime.
enum SigningGoldenStore {

    /// Env flag that switches the suite from "assert against committed goldens"
    /// to "regenerate and overwrite the committed goldens". Requires EXACTLY
    /// `"1"` so a stray/inherited truthy value can't silently flip the gate into
    /// record mode; the record run also `XCTSkip`s (never reports a plain pass).
    static var isRecording: Bool {
        ProcessInfo.processInfo.environment["RECORD_SIGNING_GOLDENS"] == "1"
    }

    private static let harnessDirectory = URL(fileURLWithPath: "\(#filePath)")
        .deletingLastPathComponent()

    static let goldenFileURL = harnessDirectory
        .appendingPathComponent("SigningGoldenVectors.json", isDirectory: false)

    /// Freshly-computed goldens are ALWAYS written here (gitignored), mirroring
    /// FigmaParity's `.actual.png`. This makes regeneration independent of env
    /// propagation into the simulator: promote with
    /// `cp SigningGoldenVectors.actual.json SigningGoldenVectors.json`.
    static let actualFileURL = harnessDirectory
        .appendingPathComponent("SigningGoldenVectors.actual.json", isDirectory: false)

    /// Load the committed goldens keyed by vector name. A missing file yields an
    /// empty map (record mode then creates it); a present-but-malformed file
    /// throws so a corrupt fixture surfaces instead of silently passing.
    static func load() throws -> [String: SigningGolden] {
        guard FileManager.default.fileExists(atPath: goldenFileURL.path) else {
            return [:]
        }
        let data = try Data(contentsOf: goldenFileURL)
        return try JSONDecoder().decode([String: SigningGolden].self, from: data)
    }

    /// Overwrite the committed golden JSON with `goldens`, sorted by key so the
    /// on-disk diff is stable across record runs.
    static func save(_ goldens: [String: SigningGolden]) throws {
        try write(goldens, to: goldenFileURL)
    }

    /// Write the always-on inspection artifact (`.actual.json`).
    static func saveActual(_ goldens: [String: SigningGolden]) throws {
        try write(goldens, to: actualFileURL)
    }

    private static func write(_ goldens: [String: SigningGolden], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(goldens)
        try FileManager.default.createDirectory(
            at: harnessDirectory,
            withIntermediateDirectories: true
        )
        try data.write(to: url)
    }
}
