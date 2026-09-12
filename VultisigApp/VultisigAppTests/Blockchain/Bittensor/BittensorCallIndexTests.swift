//
//  BittensorCallIndexTests.swift
//  VultisigAppTests
//
//  Coverage for BittensorHelper's Balances call-index selection: default
//  send signs `transfer_keep_alive` (module 5 / call 3), with
//  `transfer_allow_death` (call 0) kept available for a future
//  explicit-empty-account flow. A byte-for-byte pin of a full send lives in
//  the SigningGolden harness and `TestData/bittensor.json`; this file targets
//  just the call-index branch those goldens don't isolate.
//

import BigInt
import XCTest
@testable import VultisigApp

final class BittensorCallIndexTests: XCTestCase {

    // 32-byte placeholder hash — BittensorHelper only checks byte length, so
    // any 32-byte hex value is a valid genesis/block hash for these vectors.
    private static let hash32 = String(repeating: "ab", count: 32)

    func testModuleAndCallIndexConstantsMatchSubtensor() {
        // Pinned independently of the byte assertions below, so a wrong
        // constant can't pass by moving in lockstep with the bytes it
        // produces. moduleIndex 5: subtensor's construct_runtime!
        // (`Balances: pallet_balances = 5`). Call indices: the pinned
        // pallet-balances revision's explicit #[pallet::call_index(_)].
        XCTAssertEqual(BittensorHelper.moduleIndex, 5)
        XCTAssertEqual(BittensorHelper.transferKeepAliveIndex, 3)
        XCTAssertEqual(BittensorHelper.transferAllowDeathIndex, 0)
    }

    func testDefaultSendSignsTransferKeepAlive() throws {
        let payload = try makePayload()
        let imageHash = try BittensorHelper.getPreSignedImageHash(keysignPayload: payload)
        let bytes = try XCTUnwrap(Data(hexString: imageHash[0]))
        XCTAssertEqual(bytes[0], 5)
        XCTAssertEqual(bytes[1], 3)
    }

    func testExplicitAllowDeathSignsTransferAllowDeath() throws {
        let payload = try makePayload()
        let imageHash = try BittensorHelper.getPreSignedImageHash(keysignPayload: payload, keepAlive: false)
        let bytes = try XCTUnwrap(Data(hexString: imageHash[0]))
        XCTAssertEqual(bytes[0], 5)
        XCTAssertEqual(bytes[1], 0)
    }

    func testKeepAliveAndAllowDeathProduceDifferentSigningPayloads() throws {
        let payload = try makePayload()
        let keepAlive = try BittensorHelper.getPreSignedImageHash(keysignPayload: payload)
        let allowDeath = try BittensorHelper.getPreSignedImageHash(keysignPayload: payload, keepAlive: false)
        XCTAssertNotEqual(keepAlive, allowDeath)
    }

    func testExistentialDepositMatchesSubtensorRuntimeConstant() {
        // Subtensor `runtime/src/lib.rs`: `pub const EXISTENTIAL_DEPOSIT: u64 = 500`.
        XCTAssertEqual(BittensorHelper.existentialDeposit, BigInt(500))
    }

    // MARK: - Helpers

    private func makePayload() throws -> KeysignPayload {
        let coin = SigningGoldenFactory.coin(chain: .bittensor, ticker: "TAO", decimals: 9, curve: .ed25519)
        return SigningGoldenFactory.payload(
            coin: coin,
            toAddress: SigningGoldenFactory.recipient(.bittensor),
            toAmount: BigInt(1_000_000_000),
            chainSpecific: .Polkadot(
                recentBlockHash: Self.hash32,
                nonce: 0,
                currentBlockNumber: BigInt(5_234_567),
                specVersion: 260,
                transactionVersion: 5,
                genesisHash: Self.hash32
            )
        )
    }
}
