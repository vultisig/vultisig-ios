//
//  TonJettonAddressTests.swift
//  VultisigAppTests
//
//  The three spellings of one jetton master that have to agree: Toncenter's
//  raw upper-case, `ton-assets`' raw lower-case, and the user-friendly form
//  `TokensStore` and `Coin.contractAddress` hold. All fixtures below are the
//  real Tether jetton master.
//

import XCTest
@testable import VultisigApp

final class TonJettonAddressTests: XCTestCase {

    private let rawUpper = "0:B113A994B5024A16719F69139328EB759596C38A25F59028B146FECDC3621DFE"
    private let rawLower = "0:b113a994b5024a16719f69139328eb759596c38a25f59028b146fecdc3621dfe"
    private let bounceable = "EQCxE6mUtQJKFnGfaROTKOt1lZbDiiX1kCixRv7Nw2Id_sDs"
    private let nonBounceable = "UQCxE6mUtQJKFnGfaROTKOt1lZbDiiX1kCixRv7Nw2Id_p0p"

    func testEverySpellingOfOneMasterCanonicalizesToTheSameKey() {
        let keys = [rawUpper, rawLower, bounceable, nonBounceable].map(TonJettonAddress.canonical)
        XCTAssertEqual(Set(keys.compactMap { $0 }).count, 1, "One contract must produce one key")
        XCTAssertEqual(keys.compactMap { $0 }.count, 4, "No spelling may fail to canonicalize")
    }

    /// The canonical form is the one `TokensStore` already stores, so a
    /// discovered jetton dedups against a curated entry by `CoinMeta.uniqueId`.
    func testCanonicalFormMatchesTheCuratedContractAddress() {
        let curated = TokensStore.TokenSelectionAssets.first {
            $0.chain == .ton && $0.ticker == "USDT"
        }
        XCTAssertEqual(TonJettonAddress.canonical(rawUpper), curated?.contractAddress)
    }

    func testSurroundingWhitespaceIsIgnored() {
        XCTAssertEqual(TonJettonAddress.canonical("  \(bounceable)\n"), TonJettonAddress.canonical(bounceable))
    }

    /// Nothing that is not a TON address may produce a key: two spellings of one
    /// contract indexing separately is the failure this guards, and falling back
    /// to the raw string would cause exactly that.
    func testNonAddressesProduceNoKey() {
        XCTAssertNil(TonJettonAddress.canonical(""))
        XCTAssertNil(TonJettonAddress.canonical("   "))
        XCTAssertNil(TonJettonAddress.canonical("not-an-address"))
        XCTAssertNil(TonJettonAddress.canonical("0xd2912bc567894032f42edda72bd27bcaae79d74c"))
        // Right shape, wrong checksum — the last character is altered.
        XCTAssertNil(TonJettonAddress.canonical("EQCxE6mUtQJKFnGfaROTKOt1lZbDiiX1kCixRv7Nw2Id_sDx"))
    }
}
