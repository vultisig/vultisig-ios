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

    private static func isMigrated(_ type: FunctionCallType, coin: Coin) -> Bool {
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

    /// The mapping is an allowlist: everything not yet migrated keeps building
    /// its legacy sub-model.
    func testUnmigratedTypesMapToNil() {
        let coin = Self.makeRune()
        let stillLegacy: [FunctionCallType] = [
            .rebond, .vote, .cosmosIBC, .merge, .unmerge,
            .theSwitch, .addThorLP, .securedAsset, .withdrawSecuredAsset
        ]
        for type in stillLegacy {
            XCTAssertNil(
                type.migratedTransactionType(coin: coin, nodeAddress: Self.thorNode),
                "\(type.rawValue) has not been migrated and must keep its legacy sub-model"
            )
        }
    }

    /// Unlike LEAVE, the raw-memo form is not pinned to the chain's native
    /// asset: it deposits against one of the vault's own coins, and the form
    /// lets the user change which. Pinning RUNE here would silently attach a
    /// memo written for one asset to another.
    func testCustomMapsToTheCustomMemoIntentCarryingTheSelectedCoin() {
        let coins: [Coin] = [
            Self.makeRune(),
            FunctionCallFixture.makeTCY(),
            Self.makeCacao(),
            FunctionCallFixture.makeCoin(.thorChainStagenet, ticker: "RUNE", decimals: 8, isNative: true)
        ]

        for coin in coins {
            guard case .customMemo(let mappedCoin)? = FunctionCallType.custom.migratedTransactionType(
                coin: coin,
                nodeAddress: Self.thorNode
            ) else {
                return XCTFail("Custom must map to the custom-memo intent on \(coin.chain.rawValue)")
            }
            XCTAssertEqual(mappedCoin, coin.toCoinMeta(), "\(coin.ticker) was replaced by another asset")
        }
    }

    /// The intent's `coins` is what `needsCoinAddition` / `addCoins` read.
    func testCustomMemoIntentResolvesTheCoinItNeeds() {
        let coin = FunctionCallFixture.makeTCY()
        let intent = FunctionTransactionType.customMemo(coin: coin.toCoinMeta())
        XCTAssertEqual(intent.coins, [coin.toCoinMeta()])
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

    /// Same rule for the raw-memo form, on all four chains that offer it — and
    /// it is the *only* operation the two test networks have, so dropping it
    /// from their case list would empty their action list entirely.
    func testCustomStaysSelectableOnEveryChainThatOffersIt() {
        let chains: [Chain] = [.thorChain, .mayaChain, .thorChainChainnet, .thorChainStagenet]
        for chain in chains {
            let coin = FunctionCallFixture.makeCoin(chain, ticker: chain.ticker, decimals: 8, isNative: true)
            XCTAssertTrue(
                FunctionCallType.getCases(for: coin).contains(.custom),
                "\(chain.rawValue) no longer offers the raw-memo operation"
            )
        }
    }

    /// Rewritten from `testNoChainDefaultsToAMigratedFunction`, which this
    /// migration makes unsatisfiable rather than merely inconvenient.
    ///
    /// That assertion — no chain's `getDefault` names a migrated operation —
    /// existed because the dropdown applied the default *without publishing a
    /// change*, so a chain defaulting to a migrated type opened on a selection
    /// that built nothing. It cannot survive the raw-memo migration:
    /// `FunctionCallType.getDefault` answers `.custom` for every chain without
    /// an arm of its own, including the two THORChain test networks whose only
    /// operation it is and roughly thirty chains that offer nothing at all.
    /// Re-pointing them would mean inventing a default for chains with no case
    /// list — a value chosen to satisfy a test rather than to describe the app.
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
                Self.isMigrated(defaultType, coin: coin),
                "\(chain.rawValue) defaults to \(defaultType.rawValue), "
                    + "and the two default factories disagree about whether it still has a legacy form"
            )
        }
    }

    /// The mismatch this migration closes, asserted between the two predicates
    /// that actually held it rather than between two factories where one is
    /// derived from the other.
    ///
    /// The dropdown default decided *that* a TCY holder belongs on the raw-memo
    /// form; the form's token loading decided *which* coins it could offer. They
    /// were written as `contains("TCY")` and `== "TCY"`, so a wrapper holder was
    /// routed to a picker with nothing in it for them. Both sides now read the
    /// same relation, including the lowercase spellings the case-sensitive
    /// original missed.
    func testTheRoutingAndPickerPredicatesAgreeAcrossTheTcyFamily() {
        for ticker in ["TCY", "sTCY", "yTCY", "tcy", "stcy", "STCY"] {
            let coin = FunctionCallFixture.makeCoin(.thorChain, ticker: ticker, decimals: 8, isNative: false)

            XCTAssertEqual(
                FunctionCallType.getDefault(for: coin),
                .custom,
                "\(ticker) is a TCY-family ticker and must route to the raw-memo form"
            )
            XCTAssertTrue(
                CustomMemoAssets.supports(ticker: ticker, on: .thorChain),
                "\(ticker) routes to the raw-memo form but its picker cannot offer the coin"
            )
        }

        // The other side of the relation: the assets the form offers that are
        // *not* the TCY family must not drag the default with them.
        for ticker in ["RUNE", "RUJI"] {
            let coin = FunctionCallFixture.makeCoin(.thorChain, ticker: ticker, decimals: 8, isNative: false)

            XCTAssertEqual(FunctionCallType.getDefault(for: coin), .rebond, "\(ticker) must not route to custom")
            XCTAssertTrue(
                CustomMemoAssets.supports(ticker: ticker, on: .thorChain),
                "\(ticker) was depositable on the legacy form and must stay so"
            )
        }
    }
}
