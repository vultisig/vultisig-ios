//
//  SubstrateAllowDeathDisclosureTests.swift
//  VultisigAppTests
//

import BigInt
import XCTest
@testable import VultisigApp

final class SubstrateAllowDeathDisclosureTests: XCTestCase {

    private static let hash32 = String(repeating: "ab", count: 32)

    func testShownForTaoPayloadThatAllowsDeath() {
        XCTAssertTrue(SubstrateAllowDeathDisclosure.isShown(for: makePayload(chain: .bittensor, ticker: "TAO", allowDeath: true)))
    }

    func testShownForDotPayloadThatAllowsDeath() {
        XCTAssertTrue(SubstrateAllowDeathDisclosure.isShown(for: makePayload(chain: .polkadot, ticker: "DOT", allowDeath: true)))
    }

    func testHiddenWhenAllowDeathIsFalse() {
        let payload = makePayload(chain: .bittensor, ticker: "TAO", allowDeath: false)
        XCTAssertFalse(SubstrateAllowDeathDisclosure.isShown(for: payload))
        XCTAssertNil(SubstrateAllowDeathDisclosure.message(for: payload))
    }

    func testHiddenWhenAllowDeathIsUnset() {
        let payload = makePayload(chain: .polkadot, ticker: "DOT", allowDeath: nil)
        XCTAssertFalse(SubstrateAllowDeathDisclosure.isShown(for: payload))
        XCTAssertNil(SubstrateAllowDeathDisclosure.message(for: payload))
    }

    func testHiddenForNonPolkadotChainSpecific() {
        let coin = SigningGoldenFactory.coin(chain: .bitcoin, ticker: "BTC", decimals: 8, curve: .secp256k1)
        let payload = SigningGoldenFactory.payload(
            coin: coin,
            toAddress: SigningGoldenFactory.recipient(.bitcoin),
            toAmount: BigInt(10_000),
            chainSpecific: .UTXO(byteFee: 10, sendMaxAmount: true)
        )
        XCTAssertFalse(SubstrateAllowDeathDisclosure.isShown(for: payload))
        XCTAssertNil(SubstrateAllowDeathDisclosure.message(for: payload))
    }

    func testHiddenWithoutAPayload() {
        XCTAssertFalse(SubstrateAllowDeathDisclosure.isShown(for: nil))
        XCTAssertNil(SubstrateAllowDeathDisclosure.message(for: nil))
    }

    func testMessageNamesTheCoinTicker() throws {
        let message = try XCTUnwrap(SubstrateAllowDeathDisclosure.message(
            for: makePayload(chain: .bittensor, ticker: "TAO", allowDeath: true)
        ))
        XCTAssertTrue(message.contains("TAO"))
        XCTAssertFalse(message.contains("%@"))
        XCTAssertNotEqual(message, "allowDeathReapWarning")
    }

    // MARK: - Helpers

    private func makePayload(chain: Chain, ticker: String, allowDeath: Bool?) -> KeysignPayload {
        let coin = SigningGoldenFactory.coin(chain: chain, ticker: ticker, decimals: 10, curve: .ed25519)
        let chainSpecific: BlockChainSpecific
        if let allowDeath {
            chainSpecific = .Polkadot(
                recentBlockHash: Self.hash32,
                nonce: 0,
                currentBlockNumber: BigInt(1_000),
                specVersion: 1,
                transactionVersion: 1,
                genesisHash: Self.hash32,
                allowDeath: allowDeath
            )
        } else {
            chainSpecific = .Polkadot(
                recentBlockHash: Self.hash32,
                nonce: 0,
                currentBlockNumber: BigInt(1_000),
                specVersion: 1,
                transactionVersion: 1,
                genesisHash: Self.hash32
            )
        }
        return SigningGoldenFactory.payload(
            coin: coin,
            toAddress: SigningGoldenFactory.recipient(chain),
            toAmount: BigInt(1_000_000_000),
            chainSpecific: chainSpecific
        )
    }
}
