//
//  SuiCoinTypeTests.swift
//  VultisigApp
//
//  Pins exact, normalization-aware SUI coin-object matching: a native SUI send
//  must never pull in look-alike coins whose type merely contains "SUI" (LSTs
//  like xSUI/haSUI, SUI-named memecoins), a token send must select objects by
//  the token's fully-qualified type even when its on-chain symbol differs from
//  the display ticker (Wormhole-bridged `…::coin::COIN`), and package-address
//  form (short `0x2` vs long `0x00…02`) must not affect equality.
//

@testable import VultisigApp
import BigInt
import XCTest

final class SuiCoinTypeTests: XCTestCase {

    private let nativeShort = "0x2::sui::SUI"
    private let nativeLong = "0x0000000000000000000000000000000000000000000000000000000000000002::sui::SUI"
    private let xSUI = "0xb45f7a8e2d1c4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a::xsui::XSUI"
    // Wormhole-bridged asset: on-chain symbol/struct is COIN, not the display ticker.
    private let bridgedCoin = "0x5d4b302506645c37ff133b98c4b50a5ae14841659738d6d733d59d0d217a93bf::coin::COIN"

    // MARK: - Native matching excludes look-alikes

    func testIsNativeMatchesShortAndLongAddressForms() {
        XCTAssertTrue(SuiCoinType.isNative(nativeShort))
        XCTAssertTrue(SuiCoinType.isNative(nativeLong))
    }

    func testIsNativeRejectsLookAlikeLstAndMemecoins() {
        XCTAssertFalse(SuiCoinType.isNative(xSUI))
        XCTAssertFalse(SuiCoinType.isNative(bridgedCoin))
        XCTAssertFalse(SuiCoinType.isNative("0xabc::sssui::SSSUI"))
    }

    // MARK: - Address-form normalization

    func testNormalizeCollapsesAddressForms() {
        XCTAssertEqual(SuiCoinType.normalize(nativeShort), SuiCoinType.normalize(nativeLong))
        XCTAssertTrue(SuiCoinType.matches(nativeShort, nativeLong))
    }

    func testNormalizeIsCaseInsensitive() {
        XCTAssertTrue(SuiCoinType.matches(bridgedCoin, bridgedCoin.uppercased()))
    }

    func testNormalizeLeavesNonNativeTypesDistinct() {
        XCTAssertFalse(SuiCoinType.matches(nativeShort, xSUI))
        XCTAssertFalse(SuiCoinType.matches(bridgedCoin, xSUI))
    }

    // MARK: - expectedType resolves the record's coin type

    func testExpectedTypeForNativeRecordIsCanonicalSui() {
        XCTAssertEqual(SuiCoinType.expectedType(isNativeToken: true, contractAddress: ""), nativeShort)
    }

    func testExpectedTypeForTokenRecordIsContractAddress() {
        XCTAssertEqual(
            SuiCoinType.expectedType(isNativeToken: false, contractAddress: bridgedCoin),
            bridgedCoin
        )
    }

    // MARK: - Selection over a heterogeneous object set

    /// A wallet holding native SUI alongside an xSUI LST: a native send must
    /// select only the native object and never the LST.
    func testNativeSelectionExcludesXSui() {
        let objects = [
            ["coinType": nativeLong, "objectID": "0xnative"],
            ["coinType": xSUI, "objectID": "0xlst"]
        ]
        let selected = objects.filter { SuiCoinType.isNative($0["coinType"] ?? "") }
        XCTAssertEqual(selected.map { $0["objectID"] }, ["0xnative"])
    }

    /// A token send for a Wormhole-bridged `…::coin::COIN` asset selects its own
    /// objects (by exact type) and a separate SUI gas object — never the xSUI LST.
    func testBridgedTokenSelectionAndGasSplit() {
        let objects = [
            ["coinType": nativeLong, "objectID": "0xgas"],
            ["coinType": bridgedCoin, "objectID": "0xtoken"],
            ["coinType": xSUI, "objectID": "0xlst"]
        ]
        let tokenType = SuiCoinType.expectedType(isNativeToken: false, contractAddress: bridgedCoin)

        let tokenObjects = objects.filter { SuiCoinType.matches($0["coinType"] ?? "", tokenType) }
        let gasObjects = objects.filter { SuiCoinType.isNative($0["coinType"] ?? "") }

        XCTAssertEqual(tokenObjects.map { $0["objectID"] }, ["0xtoken"])
        XCTAssertEqual(gasObjects.map { $0["objectID"] }, ["0xgas"])
    }

    // MARK: - Payload coin filtering (keysign payload / QR bloat guard)

    /// The full set of objects a heavy wallet might own: native SUI, an LST, a
    /// bridged token, and an unrelated memecoin.
    private var heterogeneousWallet: [[String: String]] {
        [
            ["coinType": nativeLong, "objectID": "0xnative"],
            ["coinType": xSUI, "objectID": "0xlst"],
            ["coinType": bridgedCoin, "objectID": "0xtoken"],
            ["coinType": "0xfeed::moon::MOON", "objectID": "0xmemecoin"]
        ]
    }

    /// A native SUI send embeds only the native object — no LST, no bridged
    /// token, no memecoin — so the keysign payload / QR stays small.
    func testPayloadCoinsForNativeSendKeepsOnlyNative() {
        let filtered = SuiCoinType.payloadCoins(
            heterogeneousWallet,
            isNativeToken: true,
            contractAddress: ""
        )
        XCTAssertEqual(filtered.map { $0["objectID"] }, ["0xnative"])
    }

    /// A token send embeds the native SUI objects (gas) and the target token's
    /// objects only — never other held tokens (LST, memecoin).
    func testPayloadCoinsForTokenSendKeepsNativeUnionTargetTokenOnly() {
        let filtered = SuiCoinType.payloadCoins(
            heterogeneousWallet,
            isNativeToken: false,
            contractAddress: bridgedCoin
        )
        XCTAssertEqual(Set(filtered.map { $0["objectID"] }), ["0xnative", "0xtoken"])
        XCTAssertFalse(filtered.contains { $0["objectID"] == "0xlst" })
        XCTAssertFalse(filtered.contains { $0["objectID"] == "0xmemecoin" })
    }

    /// Multiple objects of the same target token (and multiple native gas
    /// objects) are all preserved — filtering by type must not cap object count.
    func testPayloadCoinsPreservesAllMatchingObjects() {
        let wallet = [
            ["coinType": nativeShort, "objectID": "0xgas1"],
            ["coinType": nativeLong, "objectID": "0xgas2"],
            ["coinType": bridgedCoin, "objectID": "0xtoken1"],
            ["coinType": bridgedCoin, "objectID": "0xtoken2"],
            ["coinType": xSUI, "objectID": "0xlst"]
        ]
        let filtered = SuiCoinType.payloadCoins(
            wallet,
            isNativeToken: false,
            contractAddress: bridgedCoin
        )
        XCTAssertEqual(
            Set(filtered.map { $0["objectID"] }),
            ["0xgas1", "0xgas2", "0xtoken1", "0xtoken2"]
        )
    }

    // MARK: - Token-send gas-object selection

    private func suiObject(_ id: String, balance: String) -> [String: String] {
        ["coinType": nativeLong, "objectID": id, "balance": balance]
    }

    /// A token send pays gas from a single SUI object. When several SUI objects
    /// cover the budget, the smallest covering one is chosen — gas is guaranteed
    /// payable while the larger objects stay available for later sends.
    func testSelectGasObjectPicksSmallestCoveringObject() {
        let coins = [
            suiObject("0xbig", balance: "10000000"),
            suiObject("0xjustEnough", balance: "3000000"),
            suiObject("0xtooSmall", balance: "1000000")
        ]
        let selected = SuiCoinType.selectGasObject(coins, gasBudget: BigInt(3_000_000))
        XCTAssertEqual(selected?["objectID"], "0xjustEnough")
    }

    /// An object whose balance equals the budget exactly is eligible.
    func testSelectGasObjectAcceptsExactBudget() {
        let coins = [
            suiObject("0xexact", balance: "3000000"),
            suiObject("0xbig", balance: "9000000")
        ]
        let selected = SuiCoinType.selectGasObject(coins, gasBudget: BigInt(3_000_000))
        XCTAssertEqual(selected?["objectID"], "0xexact")
    }

    /// When no single SUI object covers the budget, fall back to the largest
    /// object (best effort) rather than an arbitrary one.
    func testSelectGasObjectFallsBackToLargestWhenNoneCovers() {
        let coins = [
            suiObject("0xsmall", balance: "1000000"),
            suiObject("0xlargest", balance: "2500000"),
            suiObject("0xmid", balance: "2000000")
        ]
        let selected = SuiCoinType.selectGasObject(coins, gasBudget: BigInt(3_000_000))
        XCTAssertEqual(selected?["objectID"], "0xlargest")
    }

    /// Non-SUI objects never pay gas, even when their balance dwarfs the budget.
    func testSelectGasObjectIgnoresNonSuiObjects() {
        let coins = [
            ["coinType": bridgedCoin, "objectID": "0xtoken", "balance": "999999999"],
            ["coinType": xSUI, "objectID": "0xlst", "balance": "999999999"]
        ]
        XCTAssertNil(SuiCoinType.selectGasObject(coins, gasBudget: BigInt(3_000_000)))
    }

    /// A missing or unparseable `balance` is treated as zero, so such objects
    /// only win the fallback when nothing better exists.
    func testSelectGasObjectTreatsMissingBalanceAsZero() {
        let coins = [
            ["coinType": nativeLong, "objectID": "0xnoBalance"],
            suiObject("0xhasBalance", balance: "500000")
        ]
        // Neither covers a 3_000_000 budget → largest wins, and the object with
        // a real balance outranks the zero-balance one.
        let selected = SuiCoinType.selectGasObject(coins, gasBudget: BigInt(3_000_000))
        XCTAssertEqual(selected?["objectID"], "0xhasBalance")
    }

    // MARK: - Input-coin selection (transaction-size guard)

    /// Selects the fewest largest objects that cover the target, leaving the rest
    /// out so the transaction stays small.
    func testSelectInputCoinsPicksFewestLargestCoveringTarget() {
        let coins = [
            suiObject("0xa", balance: "100"),
            suiObject("0xb", balance: "300"),
            suiObject("0xc", balance: "200")
        ]
        let selected = SuiCoinType.selectInputCoins(coins, covering: BigInt(450))
        // 300 + 200 = 500 >= 450; the 100 object is left out.
        XCTAssertEqual(selected.map { $0["objectID"] }, ["0xb", "0xc"])
    }

    /// A single object that already covers the target is selected alone.
    func testSelectInputCoinsStopsAtFirstCoveringObject() {
        let coins = [
            suiObject("0xbig", balance: "1000"),
            suiObject("0xa", balance: "300"),
            suiObject("0xb", balance: "200")
        ]
        let selected = SuiCoinType.selectInputCoins(coins, covering: BigInt(500))
        XCTAssertEqual(selected.map { $0["objectID"] }, ["0xbig"])
    }

    /// The object count is capped even when more would be needed to cover the
    /// target (best effort), so the transaction never exceeds Sui's limits.
    func testSelectInputCoinsRespectsMaxObjectsCap() {
        let coins = (0..<10).map { suiObject("0x\($0)", balance: "100") }
        let selected = SuiCoinType.selectInputCoins(coins, covering: BigInt(1000), maxObjects: 3)
        XCTAssertEqual(selected.count, 3)
    }

    /// At least one object is always selected, even for a zero target.
    func testSelectInputCoinsAlwaysSelectsAtLeastOne() {
        let coins = [suiObject("0xa", balance: "100"), suiObject("0xb", balance: "200")]
        let selected = SuiCoinType.selectInputCoins(coins, covering: .zero)
        XCTAssertEqual(selected.map { $0["objectID"] }, ["0xb"])
    }

    /// Equal balances tie-break deterministically by objectID, so every
    /// co-signing device selects the identical set.
    func testSelectInputCoinsTieBreaksDeterministicallyByObjectID() {
        let coins = [
            suiObject("0xc", balance: "100"),
            suiObject("0xa", balance: "100"),
            suiObject("0xb", balance: "100")
        ]
        let selected = SuiCoinType.selectInputCoins(coins, covering: BigInt(150))
        // Two needed (100 + 100); ties broken by ascending objectID → 0xa, 0xb.
        XCTAssertEqual(selected.map { $0["objectID"] }, ["0xa", "0xb"])
    }
}
