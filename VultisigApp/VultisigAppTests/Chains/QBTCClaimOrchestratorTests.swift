//
//  QBTCClaimOrchestratorTests.swift
//  VultisigAppTests
//
//  Phase-machine + error-propagation tests for the orchestrator. The
//  TSS round and proof service are stubbed via the closure-shaped DI on
//  QBTCClaimOrchestrator. The actual MPC session bootstrap is covered
//  by manual end-to-end testing per task §14.3.
//
//  Post-qbtc#158: the orchestrator runs one BTC ECDSA MPC round and
//  POSTs `/prove` with `broadcast: true`; the proof service signs and
//  broadcasts `MsgClaimWithProof` with its own MLDSA-44 key.
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
        ClaimableUtxo(txid: String(repeating: "aa", count: 32), vout: 0, amount: 60_000, blockHeight: nil),
        ClaimableUtxo(txid: String(repeating: "bb", count: 32), vout: 1, amount: 40_000, blockHeight: nil)
    ]

    /// The orchestrator validates that the proof service's hash echoes
    /// match the locally-computed `QBTCClaimHashes`, so the mock response
    /// must echo those exact values back. Under the post-#158 flow the
    /// service-side broadcast returns a `tx_hash`; default to a populated
    /// hash so the orchestrator transitions to `.done`. Pass `txHash: nil`
    /// to simulate `BROADCAST_NOT_CONFIGURED`-style misconfiguration.
    static let mockServiceTxHash = String(repeating: "AB", count: 32)

    static func makeProofResponse(txHash: String? = mockServiceTxHash) -> ClaimProofResponse {
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
            utxos: utxos.map { ClaimProofResponseUtxo(txid: $0.txid) },
            claimerAddress: qbtcAddress,
            txHash: txHash
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
            runBtcRound: { _ in
                QBTCClaimBtcRoundResult(
                    rHex: String(repeating: "01", count: 24),
                    sHex: String(repeating: "02", count: 32)
                )
            }
        )

        var observed: [String] = []
        let cancellable = orchestrator.$phase.sink { observed.append(phaseName($0)) }

        await orchestrator.run(Self.makeRunInput())
        cancellable.cancel()

        // Final state is .done with the service-returned tx hash, uppercased.
        guard case .done(let result) = orchestrator.phase else {
            return XCTFail("expected .done, got \(orchestrator.phase)")
        }
        XCTAssertEqual(result.totalSatsClaimed, 100_000)
        XCTAssertEqual(result.txHashHex, Self.mockServiceTxHash.uppercased())

        // Phase transitions in order. The sink fires on subscribe with
        // the current value (.idle), then again on each `phase = ...`.
        XCTAssertEqual(
            observed,
            ["idle", "signingBTC", "generatingProofAndBroadcasting", "done"]
        )
    }

    // MARK: - Round runner receives expected inputs

    func testBtcRoundReceivesComputedMessageHash() async throws {
        let captured = Captured<QBTCClaimBtcRoundInput>()

        let orchestrator = makeOrchestrator(
            generateProof: { _ in Self.makeProofResponse() },
            runBtcRound: { input in
                await captured.set(input)
                return QBTCClaimBtcRoundResult(
                    rHex: String(repeating: "01", count: 24),
                    sHex: String(repeating: "02", count: 32)
                )
            }
        )

        await orchestrator.run(Self.makeRunInput())

        let captured1 = await captured.get()
        let input = try XCTUnwrap(captured1)
        XCTAssertEqual(input.btcCoin.address, Self.btcAddress)
        XCTAssertEqual(input.fastVaultPassword, "hunter2")
        XCTAssertEqual(input.messageHashHex.count, 64) // 32-byte SHA-256 hex
    }

    func testProofRequestHasBroadcastFlagSet() async throws {
        let captured = Captured<ClaimProofRequest>()

        let orchestrator = makeOrchestrator(
            generateProof: { req in
                await captured.set(req)
                return Self.makeProofResponse()
            },
            runBtcRound: { _ in
                QBTCClaimBtcRoundResult(
                    rHex: String(repeating: "01", count: 24),
                    sHex: String(repeating: "02", count: 32)
                )
            }
        )

        await orchestrator.run(Self.makeRunInput())

        let captured1 = await captured.get()
        let request = try XCTUnwrap(captured1)
        XCTAssertTrue(request.broadcast, "orchestrator must request service-side broadcast (#158)")
    }

    // MARK: - Error propagation

    func testBtcRoundFailureSurfacesAsFailedPhase() async {
        struct BtcSignError: Error {}

        let orchestrator = makeOrchestrator(
            generateProof: { _ in XCTFail("should not reach proof"); throw CancellationError() },
            runBtcRound: { _ in throw BtcSignError() }
        )

        await orchestrator.run(Self.makeRunInput())
        guard case .failed = orchestrator.phase else {
            return XCTFail("expected .failed, got \(orchestrator.phase)")
        }
    }

    func testProofHashMismatchSurfacesAsFailedPhase() async {
        // Proof service echoes hashes that don't match the locally
        // computed values — orchestrator must abort before treating the
        // service's broadcast as authoritative.
        let tamperedResponse = ClaimProofResponse(
            proof: String(repeating: "ff", count: 200),
            messageHash: String(repeating: "bb", count: 32),
            addressHash: String(repeating: "cc", count: 20),
            qbtcAddressHash: String(repeating: "dd", count: 32),
            utxos: Self.utxos.map { ClaimProofResponseUtxo(txid: $0.txid) },
            claimerAddress: Self.qbtcAddress,
            txHash: Self.mockServiceTxHash
        )

        let orchestrator = makeOrchestrator(
            generateProof: { _ in tamperedResponse },
            runBtcRound: { _ in
                QBTCClaimBtcRoundResult(
                    rHex: String(repeating: "01", count: 24),
                    sHex: String(repeating: "02", count: 32)
                )
            }
        )

        await orchestrator.run(Self.makeRunInput())
        guard case .failed = orchestrator.phase else {
            return XCTFail("expected .failed for proof hash mismatch, got \(orchestrator.phase)")
        }
    }

    func testMissingTxHashSurfacesAsFailedPhase() async {
        // Service returned a proof but no tx_hash — broadcast either
        // wasn't configured or failed. Orchestrator must fail loudly;
        // there is no fallback path.
        let orchestrator = makeOrchestrator(
            generateProof: { _ in Self.makeProofResponse(txHash: nil) },
            runBtcRound: { _ in
                QBTCClaimBtcRoundResult(
                    rHex: String(repeating: "01", count: 24),
                    sHex: String(repeating: "02", count: 32)
                )
            }
        )

        await orchestrator.run(Self.makeRunInput())
        guard case .failed = orchestrator.phase else {
            return XCTFail("expected .failed when tx_hash is nil, got \(orchestrator.phase)")
        }
    }

    func testProofServiceFailureSurfacesAsFailedPhase() async {
        struct ProofError: Error {}

        let orchestrator = makeOrchestrator(
            generateProof: { _ in throw ProofError() },
            runBtcRound: { _ in
                QBTCClaimBtcRoundResult(
                    rHex: String(repeating: "01", count: 24),
                    sHex: String(repeating: "02", count: 32)
                )
            }
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
            runBtcRound: { _ in XCTFail("should not call"); throw CancellationError() }
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
            runBtcRound: { _ in throw CancellationError() }
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
        runBtcRound: @escaping QBTCClaimOrchestrator.RunBtcRound
    ) -> QBTCClaimOrchestrator {
        QBTCClaimOrchestrator(
            generateProof: generateProof,
            runBtcRound: runBtcRound
        )
    }
}

// MARK: - Tiny test helpers

private func phaseName(_ phase: QBTCClaimPhase) -> String {
    switch phase {
    case .idle: return "idle"
    case .signingBTC: return "signingBTC"
    case .generatingProofAndBroadcasting: return "generatingProofAndBroadcasting"
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
