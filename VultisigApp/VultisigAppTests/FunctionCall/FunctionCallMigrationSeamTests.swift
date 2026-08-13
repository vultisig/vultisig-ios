//
//  FunctionCallMigrationSeamTests.swift
//  VultisigAppTests
//
//  The legacy details screen is still the only entry point for the operations
//  that have moved to `Features/FunctionTransaction/`, so it routes out
//  through `FunctionCallType.migratedTransactionType(coin:nodeAddress:)`
//  instead of building a sub-model. These pin the two ways that seam breaks:
//  a migrated operation dropped from the chain's case list (unreachable), and
//  a migrated operation left as a chain's default (the default is applied
//  without publishing a change, so the route-out never fires and the user
//  lands on a selection with no form).
//

@testable import VultisigApp
import XCTest

final class FunctionCallMigrationSeamTests: XCTestCase {

    private static let thorNode = "thor1prxy0sufdqfve6ygkwu9gswe60cle8gy02ex2w"

    private static func makeRune() -> Coin {
        FunctionCallFixture.makeRUNE()
    }

    private static func makeCacao() -> Coin {
        FunctionCallFixture.makeCoin(
            .mayaChain,
            ticker: "CACAO",
            decimals: 10,
            isNative: true,
            address: FunctionCallFixture.mayaAddress
        )
    }

    private static func isMigrated(_ type: FunctionCallType) -> Bool {
        type.migratedTransactionType(coin: makeRune(), nodeAddress: nil) != nil
    }

    private func assertIsNativeAsset(
        _ meta: CoinMeta?,
        chain: Chain,
        ticker: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(meta?.chain, chain, file: file, line: line)
        XCTAssertEqual(meta?.ticker, ticker, file: file, line: line)
        XCTAssertEqual(meta?.isNativeToken, true, file: file, line: line)
    }

    // MARK: - The mapping

    func testLeaveMapsToTheLeaveIntentOnThorchain() {
        guard case .leave(let mappedCoin, let node)? = FunctionCallType.leave.migratedTransactionType(
            coin: Self.makeRune(),
            nodeAddress: Self.thorNode
        ) else {
            return XCTFail("Leave must map to the leave intent")
        }

        assertIsNativeAsset(mappedCoin, chain: .thorChain, ticker: "RUNE")
        XCTAssertEqual(node, Self.thorNode)
    }

    func testLeaveMapsToTheLeaveIntentOnMayachain() {
        guard case .leave(let mappedCoin, let node)? = FunctionCallType.leave.migratedTransactionType(
            coin: Self.makeCacao(),
            nodeAddress: nil
        ) else {
            return XCTFail("Leave must map to the leave intent")
        }

        assertIsNativeAsset(mappedCoin, chain: .mayaChain, ticker: "CACAO")
        XCTAssertNil(node, "A caller with no node address must leave the field for the user to fill")
    }

    /// The legacy screen forced RUNE before opening the LEAVE form. Selecting
    /// Leave from a TCY wallet must still deposit against RUNE, or the memo
    /// rides a token `MsgDeposit` the node never sees.
    func testLeaveIsPinnedToTheChainsNativeAssetNotTheSelectedCoin() {
        guard case .leave(let mappedCoin, _)? = FunctionCallType.leave.migratedTransactionType(
            coin: FunctionCallFixture.makeTCY(),
            nodeAddress: Self.thorNode
        ) else {
            return XCTFail("Leave must map to the leave intent")
        }

        assertIsNativeAsset(mappedCoin, chain: .thorChain, ticker: "RUNE")
    }

    /// The intent names the native asset whether or not the vault holds it, so
    /// a vault without RUNE hits `FunctionTransactionScreen`'s shared "not in
    /// vault" error rather than signing LEAVE against TCY. The legacy
    /// `ensureRuneCoin()` silently left the non-native selection in place.
    func testLeaveTargetsTheNativeAssetEvenWhenTheVaultDoesNotHoldIt() {
        let tcy = FunctionCallFixture.makeTCY()
        let vault = FunctionCallFixture.makeVault(coins: [tcy])
        XCTAssertNil(vault.nativeCoin(for: .thorChain), "Fixture must not hold RUNE")

        guard case .leave(let mappedCoin, _)? = FunctionCallType.leave.migratedTransactionType(
            coin: tcy,
            nodeAddress: Self.thorNode
        ) else {
            return XCTFail("Leave must map to the leave intent")
        }

        assertIsNativeAsset(mappedCoin, chain: .thorChain, ticker: "RUNE")
        XCTAssertFalse(
            vault.coins.map { $0.toCoinMeta() }.contains(mappedCoin),
            "The vault cannot resolve the intent's coin, so the shared error view is what the user sees"
        )
    }

    /// The intent's `coins` is what `needsCoinAddition` / `addCoins` read.
    func testLeaveIntentResolvesTheCoinItNeeds() {
        let coin = Self.makeRune()
        let intent = FunctionTransactionType.leave(coin: coin.toCoinMeta(), node: nil)
        XCTAssertEqual(intent.coins, [coin.toCoinMeta()])
    }

    // MARK: - Unmerge

    private static func makeMergeToken(_ ticker: String = "KUJI") -> Coin {
        FunctionCallFixture.makeCoin(
            .thorChain,
            ticker: ticker,
            decimals: 8,
            isNative: false,
            address: FunctionCallFixture.thorAddress
        )
    }

    func testUnmergeMapsToTheUnmergeIntent() {
        guard case .unmerge(let mappedCoin, let denom)? = FunctionCallType.unmerge.migratedTransactionType(
            coin: Self.makeRune(),
            nodeAddress: nil
        ) else {
            return XCTFail("Unmerge must map to the unmerge intent")
        }

        assertIsNativeAsset(mappedCoin, chain: .thorChain, ticker: "RUNE")
        XCTAssertNil(denom, "RUNE is not a merge token, so the picker opens on its own first entry")
    }

    /// The legacy form pre-selected the merge token matching the coin the user
    /// opened Functions from.
    func testUnmergePreSelectsTheMergeTokenTheUserCameFrom() {
        guard case .unmerge(_, let denom)? = FunctionCallType.unmerge.migratedTransactionType(
            coin: Self.makeMergeToken(),
            nodeAddress: nil
        ) else {
            return XCTFail("Unmerge must map to the unmerge intent")
        }

        XCTAssertEqual(denom, "thor.kuji")
    }

    func testUnmergeLeavesTheDenomUnsetForATokenThatCannotBeMerged() {
        guard case .unmerge(_, let denom)? = FunctionCallType.unmerge.migratedTransactionType(
            coin: FunctionCallFixture.makeTCY(),
            nodeAddress: nil
        ) else {
            return XCTFail("Unmerge must map to the unmerge intent")
        }

        XCTAssertNil(denom, "TCY has no merge contract, so there is nothing to pre-select")
    }

    /// The unmerge wasm execute is addressed by contract and attaches no coins,
    /// so the only coin the vault has to resolve is the one paying the fee.
    func testUnmergeIsPinnedToRuneNotTheSelectedToken() {
        guard case .unmerge(let mappedCoin, _)? = FunctionCallType.unmerge.migratedTransactionType(
            coin: Self.makeMergeToken(),
            nodeAddress: nil
        ) else {
            return XCTFail("Unmerge must map to the unmerge intent")
        }

        assertIsNativeAsset(mappedCoin, chain: .thorChain, ticker: "RUNE")
    }

    /// Same fail-closed property LEAVE has: a vault that cannot pay the
    /// THORChain fee lands on the shared "not in vault" error instead of opening
    /// a form whose Continue could never produce a signable transaction.
    func testUnmergeTargetsRuneEvenWhenTheVaultDoesNotHoldIt() {
        let kuji = Self.makeMergeToken()
        let vault = FunctionCallFixture.makeVault(coins: [kuji])
        XCTAssertNil(vault.nativeCoin(for: .thorChain), "Fixture must not hold RUNE")

        guard case .unmerge(let mappedCoin, _)? = FunctionCallType.unmerge.migratedTransactionType(
            coin: kuji,
            nodeAddress: nil
        ) else {
            return XCTFail("Unmerge must map to the unmerge intent")
        }

        assertIsNativeAsset(mappedCoin, chain: .thorChain, ticker: "RUNE")
        XCTAssertFalse(
            vault.coins.map { $0.toCoinMeta() }.contains(mappedCoin),
            "The vault cannot resolve the intent's coin, so the shared error view is what the user sees"
        )
    }

    func testUnmergeIntentResolvesTheCoinItNeeds() {
        let coin = Self.makeRune()
        let intent = FunctionTransactionType.unmerge(coin: coin.toCoinMeta(), denom: nil)
        XCTAssertEqual(intent.coins, [coin.toCoinMeta()])
    }

    func testUnmergeStaysSelectableOnThorchain() {
        XCTAssertTrue(FunctionCallType.getCases(for: Self.makeRune()).contains(.unmerge))
    }

    /// Every token the picker offers has to be one the builder can address, or
    /// the wasm execute would be sent to an empty contract address.
    func testEveryOfferedMergeTokenHasAContractAndAnAsset() {
        XCTAssertFalse(MergeTokenCatalog.tokens.isEmpty)
        for token in MergeTokenCatalog.tokens {
            XCTAssertNotNil(
                MergeTokenCatalog.contractAddress(for: token.thorchainAsset),
                "\(token.thorchainAsset) is offered but has no merge contract"
            )
            XCTAssertEqual(token.asset.chain, .thorChain)
            XCTAssertEqual(token.asset.contractAddress.lowercased(), token.thorchainAsset.lowercased())
        }
    }

    /// The mapping is an allowlist: everything not yet migrated keeps building
    /// its legacy sub-model.
    func testUnmigratedTypesMapToNil() {
        let coin = Self.makeRune()
        let stillLegacy: [FunctionCallType] = [
            .rebond, .custom, .vote, .cosmosIBC, .merge,
            .theSwitch, .addThorLP, .securedAsset, .withdrawSecuredAsset
        ]
        for type in stillLegacy {
            XCTAssertNil(
                type.migratedTransactionType(coin: coin, nodeAddress: Self.thorNode),
                "\(type.rawValue) has not been migrated and must keep its legacy sub-model"
            )
        }
    }

    // MARK: - Reachability

    /// A migrated operation is reached by *selecting* it, so it has to stay in
    /// the chain's case list until the action-list screen replaces the
    /// dropdown. Dropping it here removes the feature.
    func testLeaveStaysSelectableOnBothChainsThatOfferIt() {
        XCTAssertTrue(FunctionCallType.getCases(for: Self.makeRune()).contains(.leave))
        XCTAssertTrue(FunctionCallType.getCases(for: Self.makeCacao()).contains(.leave))
    }

    /// The route-out fires on a *change* of selection. A chain whose default is
    /// a migrated type would open on a selection that builds nothing.
    func testNoChainDefaultsToAMigratedFunction() {
        for chain in Chain.allCases {
            let coin = FunctionCallFixture.makeCoin(
                chain,
                ticker: chain.ticker,
                decimals: 8,
                isNative: true
            )
            let defaultType = FunctionCallType.getDefault(for: coin)
            XCTAssertFalse(
                Self.isMigrated(defaultType),
                "\(chain.rawValue) defaults to \(defaultType.rawValue), which no longer builds a form"
            )
        }
    }
}
