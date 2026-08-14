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

    private static func isMigrated(_ type: FunctionCallType, coin: Coin = makeRune()) -> Bool {
        type.migratedTransactionType(coin: coin, nodeAddress: nil) != nil
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

    /// The mapping is an allowlist: everything not yet migrated keeps building
    /// its legacy sub-model.
    func testUnmigratedTypesMapToNil() {
        let coin = Self.makeRune()
        let stillLegacy: [FunctionCallType] = [
            .custom, .vote, .cosmosIBC, .unmerge,
            .theSwitch, .withdrawSecuredAsset
        ]
        for type in stillLegacy {
            XCTAssertNil(
                type.migratedTransactionType(coin: coin, nodeAddress: Self.thorNode),
                "\(type.rawValue) has not been migrated and must keep its legacy sub-model"
            )
        }
    }

    /// Add-LP maps to the intent the user came in on. Deliberately NOT pinned
    /// to the chain's native asset the way LEAVE is: an LP add opened from a
    /// token screen is a deposit of that token, and pinning would silently
    /// retarget it.
    func testAddThorLPMapsToTheEntryAsset() {
        let usdc = AddLPFixture.usdc()

        guard case .addThorchainLP(let mappedCoin)? = FunctionCallType.addThorLP.migratedTransactionType(
            coin: usdc,
            nodeAddress: nil
        ) else {
            return XCTFail("Add THORChain LP must map to its own intent")
        }

        XCTAssertEqual(mappedCoin, usdc.toCoinMeta())
    }

    /// The intent's `coins` is what `needsCoinAddition` / `addCoins` read, and a
    /// THORChain pool credits a RUNE account the memo has to name — so RUNE is
    /// part of what the operation needs, not an afterthought.
    func testAddThorLPIntentResolvesTheAssetAndRune() {
        let bitcoin = AddLPFixture.bitcoin()
        let coins = FunctionTransactionType.addThorchainLP(coin: bitcoin.toCoinMeta()).coins

        XCTAssertEqual(coins.first, bitcoin.toCoinMeta())
        XCTAssertTrue(
            coins.contains { $0.chain == .thorChain && $0.isNativeToken },
            "an LP deposit without a RUNE account signs a different memo entirely"
        )
    }

    /// Every chain that offers Add-LP must keep offering it: the action list is
    /// built from `getCases`, so dropping it there would make the operation
    /// migrated *and* unreachable.
    func testAddThorLPStaysSelectableOnEveryChainThatOffersIt() {
        let lpChains: [Chain] = [
            .bitcoin, .bitcoinCash, .litecoin, .dogecoin,
            .ethereum, .avalanche, .bscChain, .base, .ripple
        ]
        for chain in lpChains {
            let coin = FunctionCallFixture.makeCoin(chain, ticker: chain.ticker, decimals: 8, isNative: true)
            XCTAssertTrue(
                FunctionCallType.getCases(for: coin).contains(.addThorLP),
                "\(chain.rawValue) no longer offers Add-LP"
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

    func testMergeStaysSelectableOnThorchain() {
        XCTAssertTrue(FunctionCallType.getCases(for: Self.makeRune()).contains(.merge))
    }

    /// The route-out fires on a *change* of selection. A chain whose default is
    /// a migrated type would open on a selection that builds nothing.
    func testNoChainDefaultsToAMigratedFunction() {
    func testRebondStaysSelectableOnThorchain() {
        XCTAssertTrue(FunctionCallType.getCases(for: Self.makeRune()).contains(.rebond))
    }

    /// Whatever a chain defaults to has to be something the dropdown offers,
    /// or the selector opens on an entry it cannot show.
    func testThorchainDefaultIsOfferedByTheDropdown() {
        let rune = Self.makeRune()
        XCTAssertTrue(FunctionCallType.getCases(for: rune).contains(FunctionCallType.getDefault(for: rune)))
    }

    /// THORChain used to default by ticker — rebond for RUNE, the raw memo for
    /// TCY — and the two factories spelled that condition differently, so a
    /// holder of a TCY wrapper was routed to one operation and handed another's
    /// form. Rebond leaving the legacy screen collapses both tickers onto the
    /// raw memo, which is what removes the disagreement rather than papering
    /// over it.
    @MainActor
    func testThorchainDefaultsToTheRawMemoForEveryTicker() {
        for coin in [FunctionCallFixture.makeRUNE(), FunctionCallFixture.makeTCY()] {
            let vault = FunctionCallFixture.makeVault(coins: [coin])
            XCTAssertEqual(FunctionCallType.getDefault(for: coin), .custom, "\(coin.ticker)")
            XCTAssertEqual(
                FunctionCallInstance.getDefault(for: coin, vault: vault) == nil,
                Self.isMigrated(.custom, coin: coin),
                "\(coin.ticker): the two default factories disagree about whether a legacy form exists"
            )
        }
    }

    /// Rewritten from `testNoChainDefaultsToAMigratedFunction`, which the epic
    /// makes unsatisfiable rather than merely inconvenient.
    ///
    /// That assertion — no chain's `getDefault` names a migrated operation —
    /// existed because the dropdown applied the default *without publishing a
    /// change*, so a chain defaulting to a migrated type opened on a selection
    /// that built nothing. Integrating the ten migrations leaves several chains
    /// with no honest way to satisfy it: MayaChain offers LEAVE and the raw
    /// memo, Gaia offers IBC and SWITCH, the nine Add-LP L1s offer Add-LP
    /// alone, dYdX offers the vote alone — and after the migrations every one
    /// of those operations has its own screen. Re-pointing those defaults would
    /// mean naming an operation the chain does not offer, which is a value
    /// chosen to satisfy a test rather than to describe the app.
    ///
    /// It is also no longer the invariant that matters. Rows carry their own
    /// destination and no entry point opens the legacy screen without a
    /// preselection, so no default decides where any user lands;
    /// `FunctionActionCatalogTests
    /// .testEveryOfferedActionRoutesToAScreenThatCanBuildIt` carries the
    /// reachability half, over every operation a chain offers rather than the
    /// one it used to open on.
    ///
    /// What is left worth pinning is that the two default factories *agree*.
    /// They did not: one matched any THORChain ticker containing "TCY" and the
    /// other matched it exactly, so a holder of a TCY wrapper was routed to one
    /// operation and handed another's form. `FunctionCallInstance.getDefault`
    /// now answers nil for exactly the chains whose type default is migrated,
    /// which is the same statement made once.
    @MainActor
    func testTheTwoDefaultFactoriesAgreeOnWhichChainsHaveNoLegacyForm() {
        for chain in Chain.allCases {
            let coin = FunctionCallFixture.makeCoin(
                chain,
                ticker: chain.ticker,
                decimals: 8,
                isNative: true
            )
            let vault = FunctionCallFixture.makeVault(coins: [coin])
            let defaultType = FunctionCallType.getDefault(for: coin)

            XCTAssertEqual(
                FunctionCallInstance.getDefault(for: coin, vault: vault) == nil,
                defaultType.migratedTransactionType(coin: coin, nodeAddress: nil) != nil,
                "\(chain.rawValue) defaults to \(defaultType.rawValue), "
                    + "and the two default factories disagree about whether it still has a legacy form"
            )
        }
    }

    /// The exemption the action list made legal, stated positively.
    ///
    /// A chain whose entry resolves to `.action` never renders the dropdown at
    /// all — the passthrough builds the destination in place — and its lone
    /// case *is* its default, so "the default is migrated" is the state the
    /// action list deliberately allows rather than a defect. The nine Add-LP
    /// L1s are the first chains in it.
    func testASingleActionChainMayDefaultToItsOnlyMigratedOperation() {
        let coin = FunctionCallFixture.makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true)
        XCTAssertEqual(FunctionCallType.getCases(for: coin), [.addThorLP])
        XCTAssertEqual(FunctionCallType.getDefault(for: coin), .addThorLP)
        XCTAssertTrue(Self.isMigrated(.addThorLP))

        guard case .action(let descriptor) = FunctionActionCatalog.entry(for: coin) else {
            return XCTFail("Bitcoin must pass through to its only operation")
        }
        guard case .transaction(.addThorchainLP) = descriptor.destination else {
            return XCTFail("Bitcoin's only operation is migrated and must not route through the legacy screen")
        }
    }
}
