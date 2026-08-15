//
//  FunctionCallMigrationSeamTests.swift
//  VultisigAppTests
//
//  `FunctionCallType.migratedTransactionType(coin:nodeAddress:)` is the one
//  statement of which operations have moved to
//  `Features/FunctionTransaction/`. Both producers read it: the action list
//  asks it to decide a row's destination, and the legacy details screen still
//  asks it on selection change behind the dropdown that no entry point opens
//  any more.
//
//  These pin the mapping itself, the coin it pins an operation to, and the
//  reachability rule that outlived the dropdown: a migrated operation dropped
//  from the chain's case list disappears from the list too, because the
//  catalog is built from `getCases`.
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

    /// The function a legacy sub-model instance stands for. Exhaustive on
    /// purpose: `FunctionCallInstance.getDefault` and
    /// `FunctionCallType.getDefault` are two switches that have to agree, and
    /// adding a case to the enum should not compile until this mapping names
    /// it too.
    private static func functionType(of instance: FunctionCallInstance) -> FunctionCallType {
        switch instance {
        case .custom: return .custom
        case .vote: return .vote
        case .cosmosIBC: return .cosmosIBC
        case .theSwitch: return .theSwitch
        case .addThorLP: return .addThorLP
        }
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

    // MARK: - Withdraw secured asset

    func testWithdrawSecuredAssetMapsToItsIntent() {
        guard case .withdrawSecuredAsset(let mappedCoin)? = FunctionCallType.withdrawSecuredAsset
            .migratedTransactionType(coin: Self.makeRune(), nodeAddress: nil) else {
            return XCTFail("Withdraw secured asset must map to its intent")
        }

        assertIsNativeAsset(mappedCoin, chain: .thorChain, ticker: "RUNE")
    }

    /// The intent names the account the picker queries, never the coin the
    /// legacy screen happened to have selected: opening Functions from TCY and
    /// picking the withdrawal must still read RUNE's bank balances.
    func testWithdrawSecuredAssetIsPinnedToTheNativeAccountNotTheSelectedToken() {
        guard case .withdrawSecuredAsset(let mappedCoin)? = FunctionCallType.withdrawSecuredAsset
            .migratedTransactionType(coin: FunctionCallFixture.makeTCY(), nodeAddress: nil) else {
            return XCTFail("Withdraw secured asset must map to its intent")
        }

        assertIsNativeAsset(mappedCoin, chain: .thorChain, ticker: "RUNE")
    }

    /// A vault with no RUNE cannot ask THORChain what it holds, so it lands on
    /// the shared "not in vault" error. The legacy form answered "No Secured
    /// Assets found in vault", which says the opposite of what happened.
    func testWithdrawSecuredAssetFailsClosedWhenTheVaultHoldsNoNativeCoin() {
        let tcy = FunctionCallFixture.makeTCY()
        let vault = FunctionCallFixture.makeVault(coins: [tcy])
        XCTAssertNil(vault.nativeCoin(for: .thorChain), "Fixture must not hold RUNE")

        guard case .withdrawSecuredAsset(let mappedCoin)? = FunctionCallType.withdrawSecuredAsset
            .migratedTransactionType(coin: tcy, nodeAddress: nil) else {
            return XCTFail("Withdraw secured asset must map to its intent")
        }

        XCTAssertFalse(
            vault.coins.map { $0.toCoinMeta() }.contains(mappedCoin),
            "The vault cannot resolve the intent's coin, so the shared error view is what the user sees"
        )
    }

    func testWithdrawSecuredAssetIntentResolvesTheCoinItNeeds() {
        let coin = Self.makeRune()
        let intent = FunctionTransactionType.withdrawSecuredAsset(coin: coin.toCoinMeta())
        XCTAssertEqual(intent.coins, [coin.toCoinMeta()])
    }

    // MARK: - The mapping (merge)

    /// MERGE spends a catalog token, but the intent names the chain anchor —
    /// the form resolves the spend coin from the vault's holdings. Selecting
    /// Merge from RUNE therefore carries RUNE and no pre-selection.
    func testMergeMapsToTheMergeIntentOnTheNativeAsset() {
        guard case .merge(let mappedCoin, let denom)? = FunctionCallType.merge.migratedTransactionType(
            coin: Self.makeRune(),
            nodeAddress: nil
        ) else {
            return XCTFail("Merge must map to the merge intent")
        }

        assertIsNativeAsset(mappedCoin, chain: .thorChain, ticker: "RUNE")
        XCTAssertNil(denom, "RUNE is not a mergeable token, so there is nothing to pre-select")
    }

    /// The legacy sub-model's `preSelectToken()` matched `thor.<ticker>` of the
    /// coin the screen was on. It never fired because `ensureRuneCoin()` ran
    /// first; carrying the denom on the intent makes it real.
    func testMergePreselectsTheDenomWhenTheSelectedCoinIsMergeable() {
        let kuji = FunctionCallFixture.makeCoin(
            .thorChain,
            ticker: "KUJI",
            decimals: 8,
            isNative: false,
            address: FunctionCallFixture.thorAddress
        )

        guard case .merge(let mappedCoin, let denom)? = FunctionCallType.merge.migratedTransactionType(
            coin: kuji,
            nodeAddress: nil
        ) else {
            return XCTFail("Merge must map to the merge intent")
        }

        assertIsNativeAsset(mappedCoin, chain: .thorChain, ticker: "RUNE")
        XCTAssertEqual(denom, "thor.kuji")
    }

    /// A node address belongs to the node functions; MERGE must ignore it
    /// rather than smuggle it into the form.
    func testMergeIgnoresACarriedNodeAddress() {
        guard case .merge(_, let denom)? = FunctionCallType.merge.migratedTransactionType(
            coin: Self.makeRune(),
            nodeAddress: Self.thorNode
        ) else {
            return XCTFail("Merge must map to the merge intent")
        }

        XCTAssertNil(denom)
    }

    /// The intent's `coins` is what `needsCoinAddition` / `addCoins` read. The
    /// pickable merge tokens are vault holdings by construction, so the anchor
    /// is the only coin to resolve.
    func testMergeIntentResolvesTheCoinItNeeds() {
        let coin = Self.makeRune()
        let intent = FunctionTransactionType.merge(coin: coin.toCoinMeta(), denom: "thor.kuji")
        XCTAssertEqual(intent.coins, [coin.toCoinMeta()])
    }

    // MARK: - The mapping (unmerge)

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

    // MARK: - The mapping (rebond)

    func testRebondMapsToTheRebondIntent() {
        guard case .rebond(let mappedCoin, let node)? = FunctionCallType.rebond.migratedTransactionType(
            coin: Self.makeRune(),
            nodeAddress: Self.thorNode
        ) else {
            return XCTFail("Rebond must map to the rebond intent")
        }

        assertIsNativeAsset(mappedCoin, chain: .thorChain, ticker: "RUNE")
        XCTAssertEqual(node, Self.thorNode)
    }

    func testRebondLeavesTheNodeFieldEmptyWhenTheCallerKnowsNoNode() {
        guard case .rebond(_, let node)? = FunctionCallType.rebond.migratedTransactionType(
            coin: Self.makeRune(),
            nodeAddress: nil
        ) else {
            return XCTFail("Rebond must map to the rebond intent")
        }

        XCTAssertNil(node, "A caller with no node address must leave the field for the user to fill")
    }

    /// The legacy screen called `ensureRuneCoin()` before opening the REBOND
    /// form. Selecting Rebond from a TCY wallet must still deposit against
    /// RUNE, or the memo rides a token `MsgDeposit` the node never sees.
    func testRebondIsPinnedToRuneNotTheSelectedToken() {
        guard case .rebond(let mappedCoin, _)? = FunctionCallType.rebond.migratedTransactionType(
            coin: FunctionCallFixture.makeTCY(),
            nodeAddress: Self.thorNode
        ) else {
            return XCTFail("Rebond must map to the rebond intent")
        }

        assertIsNativeAsset(mappedCoin, chain: .thorChain, ticker: "RUNE")
    }

    /// Same fail-closed property LEAVE has: the intent names RUNE whether or
    /// not the vault holds it, so a RUNE-less vault hits the shared "not in
    /// vault" error instead of signing REBOND against TCY.
    func testRebondTargetsRuneEvenWhenTheVaultDoesNotHoldIt() {
        let tcy = FunctionCallFixture.makeTCY()
        let vault = FunctionCallFixture.makeVault(coins: [tcy])
        XCTAssertNil(vault.nativeCoin(for: .thorChain), "Fixture must not hold RUNE")

        guard case .rebond(let mappedCoin, _)? = FunctionCallType.rebond.migratedTransactionType(
            coin: tcy,
            nodeAddress: Self.thorNode
        ) else {
            return XCTFail("Rebond must map to the rebond intent")
        }

        assertIsNativeAsset(mappedCoin, chain: .thorChain, ticker: "RUNE")
        XCTAssertFalse(
            vault.coins.map { $0.toCoinMeta() }.contains(mappedCoin),
            "The vault cannot resolve the intent's coin, so the shared error view is what the user sees"
        )
    }

    func testRebondIntentResolvesTheCoinItNeeds() {
        let coin = Self.makeRune()
        let intent = FunctionTransactionType.rebond(coin: coin.toCoinMeta(), node: nil)
        XCTAssertEqual(intent.coins, [coin.toCoinMeta()])
    }

    /// The mapping is an allowlist: everything not yet migrated keeps building
    /// its legacy sub-model.
    func testUnmigratedTypesMapToNil() {
        let coin = Self.makeRune()
        let stillLegacy: [FunctionCallType] = [
            .custom, .vote, .cosmosIBC,
            .theSwitch, .addThorLP
        ]
        for type in stillLegacy {
            XCTAssertNil(
                type.migratedTransactionType(coin: coin, nodeAddress: Self.thorNode),
                "\(type.rawValue) has not been migrated and must keep its legacy sub-model"
            )
        }
    }

    // MARK: - Reachability

    /// `FunctionActionCatalog` builds a chain's rows from its case list, so a
    /// migrated operation dropped from `getCases` loses its row — the
    /// operation would be migrated *and* unreachable. The rule survived the
    /// dropdown it was written for.
    func testLeaveStaysSelectableOnBothChainsThatOfferIt() {
        XCTAssertTrue(FunctionCallType.getCases(for: Self.makeRune()).contains(.leave))
        XCTAssertTrue(FunctionCallType.getCases(for: Self.makeCacao()).contains(.leave))
    }

    /// `SECURE-` is the only route out of a secured position, so losing it from
    /// the dropdown is not a cosmetic regression.
    func testWithdrawSecuredAssetStaysSelectableOnThorchain() {
        XCTAssertTrue(FunctionCallType.getCases(for: Self.makeRune()).contains(.withdrawSecuredAsset))
    }

    func testMergeStaysSelectableOnThorchain() {
        XCTAssertTrue(FunctionCallType.getCases(for: Self.makeRune()).contains(.merge))
    }

    func testRebondStaysSelectableOnThorchain() {
        XCTAssertTrue(FunctionCallType.getCases(for: Self.makeRune()).contains(.rebond))
    }

    /// Whatever a chain defaults to has to be something the dropdown offers,
    /// or the selector opens on an entry it cannot show.
    func testThorchainDefaultIsOfferedByTheDropdown() {
        let rune = Self.makeRune()
        XCTAssertTrue(FunctionCallType.getCases(for: rune).contains(FunctionCallType.getDefault(for: rune)))
    }

    /// `setupForm()` runs both default factories back to back — the type picks
    /// the selector's label and the instance builds the form under it. THORChain
    /// used to disagree by ticker (rebond for RUNE, custom for TCY); rebond
    /// leaving the legacy screen collapses both to custom, and they must stay
    /// in step or the dropdown names one function over another's form.
    @MainActor
    func testThorchainDefaultsAgreeAcrossBothFactories() {
        for coin in [FunctionCallFixture.makeRUNE(), FunctionCallFixture.makeTCY()] {
            let vault = FunctionCallFixture.makeVault(coins: [coin])
            XCTAssertEqual(FunctionCallType.getDefault(for: coin), .custom, "\(coin.ticker)")
            XCTAssertEqual(
                Self.functionType(of: FunctionCallInstance.getDefault(for: coin, vault: vault)),
                FunctionCallType.getDefault(for: coin),
                "\(coin.ticker): the two default factories must name the same function"
            )
        }
    }

    /// Kept, with a narrower job than it was written for.
    ///
    /// It was the guard on the only entry point there was: the dropdown
    /// applied `getDefault` without publishing a change, so a chain defaulting
    /// to a migrated type opened on a selection that built nothing. Rows carry
    /// their own destination, so no default decides where a user lands any
    /// more, and the invariant that now protects them is
    /// `FunctionActionCatalogTests
    /// .testEveryOfferedActionRoutesToAScreenThatCanBuildIt`, which is
    /// strictly stronger — it covers every operation a chain offers, not just
    /// the one it used to open on.
    ///
    /// This still fails loudly if the dropdown path is re-entered before the
    /// legacy shell is deleted, and it costs one `Chain.allCases` walk.
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
