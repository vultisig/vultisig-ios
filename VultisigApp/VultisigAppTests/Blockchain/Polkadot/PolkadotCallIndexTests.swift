//
//  PolkadotCallIndexTests.swift
//  VultisigAppTests
//
//  Coverage for PolkadotHelper's Balances call-index selection on Asset Hub
//  (module 10): a send signs `transfer_keep_alive` (call 3) unless the
//  payload's `allow_death` asks for `transfer_allow_death` (call 0). A
//  byte-for-byte pin of both full sends lives in `TestData/dot.json`; this file
//  targets just the call-index branch, on the pre-image and the signed
//  extrinsic.
//

import BigInt
import WalletCore
import XCTest
@testable import VultisigApp

final class PolkadotCallIndexTests: XCTestCase {

    private static let hash32 = "0x" + String(repeating: "ab", count: 32)

    func testUnsetAllowDeathSignsTransferKeepAlive() throws {
        let bytes = try preImage(makePayload())
        XCTAssertEqual(bytes[0], 10)
        XCTAssertEqual(bytes[1], 3)
    }

    func testAllowDeathPayloadSignsTransferAllowDeath() throws {
        let bytes = try preImage(makePayload(allowDeath: true))
        XCTAssertEqual(bytes[0], 10)
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
            let imageHashes = try PolkadotHelper.getPreSignedImageHash(keysignPayload: payload)
            let signatures = try SigningGoldenSigner.signatures(forImageHashes: imageHashes, curve: .ed25519)

            let signed = try PolkadotHelper.getSignedTransaction(keysignPayload: payload, signatures: signatures)

            let destination = try XCTUnwrap(AnyAddress(string: payload.toAddress, coin: .polkadot)).data
            let signedCall = Data([10, allowDeath ? 0 : 3, 0x00]) + destination
            let otherCall = Data([10, allowDeath ? 3 : 0, 0x00]) + destination
            let raw = try XCTUnwrap(Data(hexString: signed.rawTransaction))
            XCTAssertTrue(try preImage(payload).starts(with: signedCall))
            XCTAssertNotNil(raw.range(of: signedCall))
            XCTAssertNil(raw.range(of: otherCall))
        }
    }

    // MARK: - Helpers

    private func preImage(_ payload: KeysignPayload) throws -> Data {
        let imageHash = try PolkadotHelper.getPreSignedImageHash(keysignPayload: payload)
        return try XCTUnwrap(Data(hexString: imageHash[0]))
    }

    private func makePayload(allowDeath: Bool? = nil) throws -> KeysignPayload {
        let coin = SigningGoldenFactory.coin(chain: .polkadot, ticker: "DOT", decimals: 10, curve: .ed25519)
        let chainSpecific: BlockChainSpecific
        if let allowDeath {
            chainSpecific = .Polkadot(
                recentBlockHash: Self.hash32,
                nonce: 0,
                currentBlockNumber: BigInt(18_000_000),
                specVersion: 1_006_001,
                transactionVersion: 26,
                genesisHash: Self.hash32,
                allowDeath: allowDeath
            )
        } else {
            chainSpecific = .Polkadot(
                recentBlockHash: Self.hash32,
                nonce: 0,
                currentBlockNumber: BigInt(18_000_000),
                specVersion: 1_006_001,
                transactionVersion: 26,
                genesisHash: Self.hash32
            )
        }
        return SigningGoldenFactory.payload(
            coin: coin,
            toAddress: SigningGoldenFactory.recipient(.polkadot),
            toAmount: BigInt(10_000_000_000),
            chainSpecific: chainSpecific
        )
    }
}
