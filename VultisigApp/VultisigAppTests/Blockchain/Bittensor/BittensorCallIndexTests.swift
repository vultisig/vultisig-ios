//
//  BittensorCallIndexTests.swift
//  VultisigAppTests
//
//  Coverage for BittensorHelper's Balances call-index selection: a send signs
//  `transfer_keep_alive` (module 5 / call 3) unless the payload's
//  `allow_death` asks for `transfer_allow_death` (call 0). A byte-for-byte pin
//  of both full sends lives in `TestData/bittensor.json`; this file targets
//  just the call-index branch, on the pre-image and the signed extrinsic.
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

    func testUnsetAllowDeathSignsTransferKeepAlive() throws {
        let bytes = try preImage(makePayload())
        XCTAssertEqual(bytes[0], 5)
        XCTAssertEqual(bytes[1], 3)
    }

    func testAllowDeathPayloadSignsTransferAllowDeath() throws {
        let bytes = try preImage(makePayload(allowDeath: true))
        XCTAssertEqual(bytes[0], 5)
        XCTAssertEqual(bytes[1], 0)
    }

    func testExplicitAllowDeathFalseMatchesUnset() throws {
        XCTAssertEqual(try preImage(makePayload(allowDeath: false)), try preImage(makePayload()))
    }

    func testAllowDeathChangesOnlyTheCallIndex() throws {
        let keepAlive = try preImage(makePayload())
        let allowDeath = try preImage(makePayload(allowDeath: true))

        XCTAssertEqual(keepAlive.count, allowDeath.count)
        let differing = zip(keepAlive, allowDeath).enumerated().filter { $0.element.0 != $0.element.1 }.map(\.offset)
        XCTAssertEqual(differing, [1])
    }

    func testSignedExtrinsicCarriesTheCallTheCoSignersHashed() throws {
        for allowDeath in [false, true] {
            let payload = try makePayload(allowDeath: allowDeath)
            let imageHashes = try BittensorHelper.getPreSignedImageHash(keysignPayload: payload)
            let signatures = try SigningGoldenSigner.signatures(forImageHashes: imageHashes, curve: .ed25519)

            let signed = try BittensorHelper.getSignedTransaction(keysignPayload: payload, signatures: signatures)

            // The extrinsic ends with the call data, which the pre-image opens with.
            let callLength = 2 + 1 + 32 + BittensorHelper.compactEncode(payload.toAmount).count
            let raw = try XCTUnwrap(Data(hexString: signed.rawTransaction))
            let imageBytes = try XCTUnwrap(Data(hexString: imageHashes[0]))
            XCTAssertEqual(raw.suffix(callLength), imageBytes.prefix(callLength))
            XCTAssertEqual(raw.suffix(callLength).prefix(2), Data([5, allowDeath ? 0 : 3]))
        }
    }

    func testExistentialDepositMatchesSubtensorRuntimeConstant() {
        // Subtensor `runtime/src/lib.rs`: `pub const EXISTENTIAL_DEPOSIT: u64 = 500`.
        XCTAssertEqual(BittensorHelper.existentialDeposit, BigInt(500))
    }

    // MARK: - Helpers

    private func preImage(_ payload: KeysignPayload) throws -> Data {
        let imageHash = try BittensorHelper.getPreSignedImageHash(keysignPayload: payload)
        return try XCTUnwrap(Data(hexString: imageHash[0]))
    }

    private func makePayload(allowDeath: Bool? = nil) throws -> KeysignPayload {
        let coin = SigningGoldenFactory.coin(chain: .bittensor, ticker: "TAO", decimals: 9, curve: .ed25519)
        let chainSpecific: BlockChainSpecific
        if let allowDeath {
            chainSpecific = .Polkadot(
                recentBlockHash: Self.hash32,
                nonce: 0,
                currentBlockNumber: BigInt(5_234_567),
                specVersion: 260,
                transactionVersion: 5,
                genesisHash: Self.hash32,
                allowDeath: allowDeath
            )
        } else {
            chainSpecific = .Polkadot(
                recentBlockHash: Self.hash32,
                nonce: 0,
                currentBlockNumber: BigInt(5_234_567),
                specVersion: 260,
                transactionVersion: 5,
                genesisHash: Self.hash32
            )
        }
        return SigningGoldenFactory.payload(
            coin: coin,
            toAddress: SigningGoldenFactory.recipient(.bittensor),
            toAmount: BigInt(1_000_000_000),
            chainSpecific: chainSpecific
        )
    }
}
