//
//  QBTCClaimOrchestratorTests.swift
//  VultisigAppTests
//
//  Phase-machine + error-propagation tests for the orchestrator. The
//  TSS rounds and external services are stubbed via the closure-shaped
//  DI on QBTCClaimOrchestrator. The actual MPC session bootstrap is
//  covered by manual end-to-end testing per task §14.3.
//

import Combine
@testable import VultisigApp
import XCTest

@MainActor
final class QBTCClaimOrchestratorTests: XCTestCase {
    // MARK: - Fixtures

    /// secp256k1 generator point, valid 33-byte compressed pubkey.
    static let btcCompressedPubkeyHex =
        "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
    /// 32 bytes. Stand-in for an MLDSA pubkey (real ones are ~1300B; size
    /// doesn't matter for these tests).
    static let mldsaPubkeyHex = String(repeating: "ab", count: 32)

    static let btcAddress = "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa" // P2PKH
    static let qbtcAddress = "qbtc1abc"

    static let utxos = [
        ClaimableUtxo(txid: String(repeating: "aa", count: 32), vout: 0, amount: 60_000),
        ClaimableUtxo(txid: String(repeating: "bb", count: 32), vout: 1, amount: 40_000)
    ]

    /// The orchestrator now validates that the proof service's hash
    /// echoes match the locally-computed `QBTCClaimHashes`, so the mock
    /// response must echo those exact values back.
    static func makeProofResponse() -> ClaimProofResponse {
        // swiftlint:disable:next force_try
        let hashes = try! QBTCClaimHashes.computeAll(
            btcAddress: btcAddress,
            // swiftlint:disable:next force_unwrapping
            compressedPubkey: Data(hexString: btcCompressedPubkeyHex)!,
            qbtcAddress: qbtcAddress,
            chainId: QBTCClaimConfig.chainId
        )
        return ClaimProofResponse(
            proof: String(repeating: "ff", count: 200),
            messageHash: hashes.messageHash.toHexString(),
            addressHash: hashes.addressHash.toHexString(),
            qbtcAddressHash: hashes.qbtcAddressHash.toHexString(),
            utxos: utxos.map(ClaimProofUtxoRef.init),
            claimerAddress: qbtcAddress
        )
    }

    static func makeAccountInfo() -> QBTCClaimAccountInfo {
        QBTCClaimAccountInfo(
            accountNumber: 42,
            sequence: 3,
            latestBlockHeight: 12_345,
            timeoutNs: 9_000_000_000_000
        )
    }

    static func makeRunInput() -> QBTCClaimRunInput {
        let btcAsset = CoinMeta(
            chain: .bitcoin,
            ticker: "BTC",
            logo: "btc",
            decimals: 8,
            priceProviderId: "bitcoin",
            contractAddress: "",
            isNativeToken: true
        )
        let qbtcAsset = CoinMeta(
            chain: .qbtc,
            ticker: "QBTC",
            logo: "qbtc",
            decimals: 8,
            priceProviderId: "qbtc",
            contractAddress: "",
            isNativeToken: true
        )
        return QBTCClaimRunInput(
            vault: Vault(name: "TestVault"),
            btcCoin: Coin(asset: btcAsset, address: btcAddress, hexPublicKey: btcCompressedPubkeyHex),
            qbtcCoin: Coin(asset: qbtcAsset, address: qbtcAddress, hexPublicKey: mldsaPubkeyHex),
            utxos: utxos,
            fastVaultPassword: "hunter2"
        )
    }

    // MARK: - Happy path

    func testRunHappyPathTransitionsThroughAllPhases() async throws {
        let orchestrator = makeOrchestrator(
            generateProof: { _ in Self.makeProofResponse() },
            fetchAccountInfo: { _ in Self.makeAccountInfo() },
            broadcastClaim: { _, hash in hash },  // echo the local hash
            runBtcRound: { _ in
                QBTCClaimBtcRoundResult(
                    rHex: String(repeating: "01", count: 24),
                    sHex: String(repeating: "02", count: 32)
                )
            },
            runMldsaRound: { _ in Data(repeating: 0xef, count: 96) }
        )

        var observed: [String] = []
        let cancellable = orchestrator.$phase.sink { observed.append(phaseName($0)) }

        await orchestrator.run(Self.makeRunInput())
        cancellable.cancel()

        // Final state is .done with the locally-computed tx hash.
        guard case .done(let result) = orchestrator.phase else {
            return XCTFail("expected .done, got \(orchestrator.phase)")
        }
        XCTAssertEqual(result.totalSatsClaimed, 100_000)
        XCTAssertFalse(result.txHashHex.isEmpty)
        XCTAssertEqual(result.txHashHex, result.txHashHex.uppercased())

        // Phase transitions in order. The sink fires on subscribe with
        // the current value (.idle), then again on each `phase = ...`.
        XCTAssertEqual(
            observed,
            ["idle", "signingBTC", "generatingProof", "signingMLDSA", "broadcasting", "done"]
        )
    }

    // MARK: - Round runners receive expected inputs

    func testBtcRoundReceivesComputedMessageHash() async throws {
        let captured = Captured<QBTCClaimBtcRoundInput>()

        let orchestrator = makeOrchestrator(
            generateProof: { _ in Self.makeProofResponse() },
            fetchAccountInfo: { _ in Self.makeAccountInfo() },
            broadcastClaim: { _, hash in hash },
            runBtcRound: { input in
                await captured.set(input)
                return QBTCClaimBtcRoundResult(
                    rHex: String(repeating: "01", count: 24),
                    sHex: String(repeating: "02", count: 32)
                )
            },
            runMldsaRound: { _ in Data(repeating: 0xef, count: 96) }
        )

        await orchestrator.run(Self.makeRunInput())

        let captured1 = await captured.get()
        let input = try XCTUnwrap(captured1)
        XCTAssertEqual(input.btcCoin.address, Self.btcAddress)
        XCTAssertEqual(input.fastVaultPassword, "hunter2")
        XCTAssertEqual(input.messageHashHex.count, 64) // 32-byte SHA-256 hex
    }

    func testMldsaRoundReceivesSignDocHash() async throws {
        let captured = Captured<QBTCClaimMldsaRoundInput>()

        let orchestrator = makeOrchestrator(
            generateProof: { _ in Self.makeProofResponse() },
            fetchAccountInfo: { _ in Self.makeAccountInfo() },
            broadcastClaim: { _, hash in hash },
            runBtcRound: { _ in
                QBTCClaimBtcRoundResult(
                    rHex: String(repeating: "01", count: 24),
                    sHex: String(repeating: "02", count: 32)
                )
            },
            runMldsaRound: { input in
                await captured.set(input)
                return Data(repeating: 0xef, count: 96)
            }
        )

        await orchestrator.run(Self.makeRunInput())

        let captured1 = await captured.get()
        let input = try XCTUnwrap(captured1)
        XCTAssertEqual(input.qbtcCoin.address, Self.qbtcAddress)
        XCTAssertEqual(input.fastVaultPassword, "hunter2")
        XCTAssertEqual(input.signDocHashHex.count, 64)
    }

    // MARK: - Error propagation

    func testBtcRoundFailureSurfacesAsFailedPhase() async {
        struct BtcSignError: Error {}

        let orchestrator = makeOrchestrator(
            generateProof: { _ in XCTFail("should not reach proof"); throw CancellationError() },
            fetchAccountInfo: { _ in XCTFail("should not reach account info"); throw CancellationError() },
            broadcastClaim: { _, _ in XCTFail("should not broadcast"); throw CancellationError() },
            runBtcRound: { _ in throw BtcSignError() },
            runMldsaRound: { _ in XCTFail("should not reach mldsa"); throw CancellationError() }
        )

        await orchestrator.run(Self.makeRunInput())
        guard case .failed = orchestrator.phase else {
            return XCTFail("expected .failed, got \(orchestrator.phase)")
        }
    }

    func testProofHashMismatchSurfacesAsFailedPhase() async {
        // Proof service echoes hashes that don't match the locally
        // computed values — orchestrator must abort before signing
        // round 2 instead of trusting the response.
        let tamperedResponse = ClaimProofResponse(
            proof: String(repeating: "ff", count: 200),
            messageHash: String(repeating: "bb", count: 32),
            addressHash: String(repeating: "cc", count: 20),
            qbtcAddressHash: String(repeating: "dd", count: 32),
            utxos: Self.utxos.map(ClaimProofUtxoRef.init),
            claimerAddress: Self.qbtcAddress
        )

        let orchestrator = makeOrchestrator(
            generateProof: { _ in tamperedResponse },
            fetchAccountInfo: { _ in Self.makeAccountInfo() },
            broadcastClaim: { _, _ in XCTFail("should not broadcast"); throw CancellationError() },
            runBtcRound: { _ in
                QBTCClaimBtcRoundResult(
                    rHex: String(repeating: "01", count: 24),
                    sHex: String(repeating: "02", count: 32)
                )
            },
            runMldsaRound: { _ in XCTFail("should not reach mldsa"); throw CancellationError() }
        )

        await orchestrator.run(Self.makeRunInput())
        guard case .failed = orchestrator.phase else {
            return XCTFail("expected .failed for proof hash mismatch, got \(orchestrator.phase)")
        }
    }

    func testProofServiceFailureSurfacesAsFailedPhase() async {
        struct ProofError: Error {}

        let orchestrator = makeOrchestrator(
            generateProof: { _ in throw ProofError() },
            fetchAccountInfo: { _ in Self.makeAccountInfo() },
            broadcastClaim: { _, _ in XCTFail("should not broadcast"); throw CancellationError() },
            runBtcRound: { _ in
                QBTCClaimBtcRoundResult(
                    rHex: String(repeating: "01", count: 24),
                    sHex: String(repeating: "02", count: 32)
                )
            },
            runMldsaRound: { _ in XCTFail("should not reach mldsa"); throw CancellationError() }
        )

        await orchestrator.run(Self.makeRunInput())
        guard case .failed = orchestrator.phase else {
            return XCTFail("expected .failed, got \(orchestrator.phase)")
        }
    }

    func testInvalidBtcPubkeyShortCircuits() async {
        let badAsset = CoinMeta(
            chain: .bitcoin, ticker: "BTC", logo: "btc",
            decimals: 8, priceProviderId: "bitcoin",
            contractAddress: "", isNativeToken: true
        )
        let bad = QBTCClaimRunInput(
            vault: Vault(name: "TestVault"),
            btcCoin: Coin(asset: badAsset, address: Self.btcAddress, hexPublicKey: "not-hex"),
            qbtcCoin: Self.makeRunInput().qbtcCoin,
            utxos: Self.utxos,
            fastVaultPassword: "x"
        )

        let orchestrator = makeOrchestrator(
            generateProof: { _ in XCTFail("should not call"); throw CancellationError() },
            fetchAccountInfo: { _ in XCTFail("should not call"); throw CancellationError() },
            broadcastClaim: { _, _ in XCTFail("should not call"); throw CancellationError() },
            runBtcRound: { _ in XCTFail("should not call"); throw CancellationError() },
            runMldsaRound: { _ in XCTFail("should not call"); throw CancellationError() }
        )

        await orchestrator.run(bad)
        guard case .failed = orchestrator.phase else {
            return XCTFail("expected .failed for invalid pubkey, got \(orchestrator.phase)")
        }
    }

    // MARK: - Reset

    func testResetReturnsToIdle() async {
        let orchestrator = makeOrchestrator(
            generateProof: { _ in throw CancellationError() },
            fetchAccountInfo: { _ in throw CancellationError() },
            broadcastClaim: { _, _ in throw CancellationError() },
            runBtcRound: { _ in throw CancellationError() },
            runMldsaRound: { _ in throw CancellationError() }
        )
        await orchestrator.run(Self.makeRunInput())
        guard case .failed = orchestrator.phase else {
            return XCTFail("setup expected .failed")
        }
        orchestrator.reset()
        XCTAssertEqual(orchestrator.phase, .idle)
    }

    // MARK: - Helpers

    private func makeOrchestrator(
        generateProof: @escaping QBTCClaimOrchestrator.GenerateProof,
        fetchAccountInfo: @escaping QBTCClaimOrchestrator.FetchAccountInfo,
        broadcastClaim: @escaping QBTCClaimOrchestrator.BroadcastClaim,
        runBtcRound: @escaping QBTCClaimOrchestrator.RunBtcRound,
        runMldsaRound: @escaping QBTCClaimOrchestrator.RunMldsaRound
    ) -> QBTCClaimOrchestrator {
        QBTCClaimOrchestrator(
            generateProof: generateProof,
            fetchAccountInfo: fetchAccountInfo,
            broadcastClaim: broadcastClaim,
            runBtcRound: runBtcRound,
            runMldsaRound: runMldsaRound
        )
    }
}

// MARK: - Tiny test helpers

private func phaseName(_ phase: QBTCClaimPhase) -> String {
    switch phase {
    case .idle: return "idle"
    case .signingBTC: return "signingBTC"
    case .generatingProof: return "generatingProof"
    case .signingMLDSA: return "signingMLDSA"
    case .broadcasting: return "broadcasting"
    case .done: return "done"
    case .failed: return "failed"
    }
}

/// Captures a value asynchronously written from a closure and read back
/// from the test body. Actor-isolated to satisfy `Sendable` requirements
/// on `@escaping` closures.
private actor Captured<T: Sendable> {
    private var stored: T?
    func set(_ newValue: T) { stored = newValue }
    func get() -> T? { stored }
}
