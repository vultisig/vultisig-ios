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

    // MARK: - dYdX vote

    private static func makeDydx() -> Coin {
        FunctionCallFixture.makeCoin(
            .dydx,
            ticker: "DYDX",
            decimals: 18,
            isNative: true,
            address: "dydx1xyzfixturedydxchainvaultaddress000000"
        )
    }

    func testVoteMapsToTheDydxVoteIntent() {
        guard case .dydxVote(let mappedCoin)? = FunctionCallType.vote.migratedTransactionType(
            coin: Self.makeDydx(),
            nodeAddress: nil
        ) else {
            return XCTFail("Vote must map to the dYdX vote intent")
        }

        assertIsNativeAsset(mappedCoin, chain: .dydx, ticker: "DYDX")
    }

    /// A node address carried over from a previous form means nothing to a
    /// ballot; the intent has nowhere to put one and must not grow a field for
    /// it by accident.
    func testVoteIgnoresACarriedOverNodeAddress() {
        XCTAssertEqual(
            FunctionCallType.vote.migratedTransactionType(coin: Self.makeDydx(), nodeAddress: Self.thorNode),
            FunctionCallType.vote.migratedTransactionType(coin: Self.makeDydx(), nodeAddress: nil)
        )
    }

    /// Same fail-closed property LEAVE has: the intent names dYdX's native
    /// asset whether or not the vault holds it, so a vault that cannot pay the
    /// fee lands on the shared "not in vault" error instead of opening a ballot
    /// that could never be signed.
    func testVoteTargetsDydxsNativeAssetEvenWhenTheVaultDoesNotHoldIt() {
        let rune = Self.makeRune()
        let vault = FunctionCallFixture.makeVault(coins: [rune])

        guard case .dydxVote(let mappedCoin)? = FunctionCallType.vote.migratedTransactionType(
            coin: rune,
            nodeAddress: nil
        ) else {
            return XCTFail("Vote must map to the dYdX vote intent")
        }

        assertIsNativeAsset(mappedCoin, chain: .dydx, ticker: "DYDX")
        XCTAssertFalse(
            vault.coins.map { $0.toCoinMeta() }.contains(mappedCoin),
            "The vault cannot resolve the intent's coin, so the shared error view is what the user sees"
        )
    }

    func testVoteIntentResolvesTheCoinItNeeds() {
        let coin = Self.makeDydx()
        let intent = FunctionTransactionType.dydxVote(coin: coin.toCoinMeta())
        XCTAssertEqual(intent.coins, [coin.toCoinMeta()])
    }

    func testVoteStaysSelectableOnDydx() {
        XCTAssertTrue(FunctionCallType.getCases(for: Self.makeDydx()).contains(.vote))
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

    func testRebondStaysSelectableOnThorchain() {
        XCTAssertTrue(FunctionCallType.getCases(for: Self.makeRune()).contains(.rebond))
    }

    // MARK: - IBC

    /// Unlike LEAVE, the IBC intent must NOT be pinned to the chain's native
    /// asset: an `ibc/…` or `factory/…` token is as transferable as the chain's
    /// own coin, and pinning would silently transfer the wrong asset.
    func testIbcMapsToTheTransferIntentOnTheSelectedCoin() {
        for coin in [FunctionCallFixture.makeKUJI(), FunctionCallFixture.makeATOM()] {
            guard case .ibcTransfer(let mappedCoin, let destination)? =
                    FunctionCallType.cosmosIBC.migratedTransactionType(coin: coin, nodeAddress: nil) else {
                return XCTFail("IBC must map to the transfer intent on \(coin.chain.rawValue)")
            }

            XCTAssertEqual(mappedCoin, coin.toCoinMeta())
            XCTAssertNil(destination, "The list is entered cold — no route is pre-selected")
        }
    }

    /// A non-native asset keeps its own identity through the mapping. The
    /// legacy screen had no pinning here either; this pins that it stays that
    /// way as the other migrations add `ensureRuneCoin`-style pins.
    func testIbcDoesNotPinToTheChainsNativeAsset() {
        let ibcToken = FunctionCallFixture.makeCoin(
            .kujira,
            ticker: "USK",
            decimals: 6,
            isNative: false,
            address: FunctionCallFixture.kujiAddress
        )

        guard case .ibcTransfer(let mappedCoin, _)? =
                FunctionCallType.cosmosIBC.migratedTransactionType(coin: ibcToken, nodeAddress: nil) else {
            return XCTFail("IBC must map to the transfer intent")
        }

        XCTAssertEqual(mappedCoin.ticker, "USK")
        XCTAssertEqual(mappedCoin.isNativeToken, false)
    }

    func testIbcIntentResolvesTheCoinItNeeds() {
        let coin = FunctionCallFixture.makeKUJI()
        let intent = FunctionTransactionType.ibcTransfer(coin: coin.toCoinMeta(), destinationChain: nil)
        XCTAssertEqual(intent.coins, [coin.toCoinMeta()])
    }

    // MARK: - Reachability

    func testIbcStaysSelectableOnEveryChainThatOffersIt() {
        for coin in [
            FunctionCallFixture.makeKUJI(),
            FunctionCallFixture.makeATOM(),
            FunctionCallFixture.makeCoin(.osmosis, ticker: "OSMO", decimals: 6, isNative: true)
        ] {
            XCTAssertTrue(
                FunctionCallType.getCases(for: coin).contains(.cosmosIBC),
                "\(coin.chain.rawValue) must keep offering IBC — the catalog builds its rows from getCases"
            )
        }
    }

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

    /// `SECURE-` is the only route out of a secured position, so losing it from
    /// the dropdown is not a cosmetic regression.
    func testWithdrawSecuredAssetStaysSelectableOnThorchain() {
        XCTAssertTrue(FunctionCallType.getCases(for: Self.makeRune()).contains(.withdrawSecuredAsset))
    }

    /// Whatever a chain defaults to has to be something the dropdown offers,
    /// or the selector opens on an entry it cannot show.
    func testThorchainDefaultIsOfferedByTheDropdown() {
        let rune = Self.makeRune()
        XCTAssertTrue(FunctionCallType.getCases(for: rune).contains(FunctionCallType.getDefault(for: rune)))
    }

    /// dYdX offers exactly one operation, that operation is migrated, and the
    /// entry point therefore opens the migrated screen directly rather than
    /// consulting `getDefault` at all. Its `getDefault` stays `.vote` because
    /// that is honestly the only thing the chain does.
    func testASingleActionChainMayDefaultToItsOnlyMigratedOperation() {
        let coin = Self.makeDydx()
        XCTAssertEqual(FunctionCallType.getCases(for: coin), [.vote])
        XCTAssertEqual(FunctionCallType.getDefault(for: coin), .vote)
        XCTAssertTrue(Self.isMigrated(.vote))

        guard case .action(let descriptor) = FunctionActionCatalog.entry(for: coin) else {
            return XCTFail("dYdX must pass through to its only operation")
        }
        guard case .transaction(.dydxVote) = descriptor.destination else {
            return XCTFail("dYdX's only operation is migrated and must not route through the legacy screen")
        }
    }
}
