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

    /// The mapping is an allowlist: everything not yet migrated keeps building
    /// its legacy sub-model.
    func testUnmigratedTypesMapToNil() {
        let coin = Self.makeRune()
        let stillLegacy: [FunctionCallType] = [
            .rebond, .custom, .cosmosIBC, .merge, .unmerge,
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

    /// `FunctionActionCatalog` builds a chain's rows from its case list, so a
    /// migrated operation dropped from `getCases` loses its row — the
    /// operation would be migrated *and* unreachable. The rule survived the
    /// dropdown it was written for.
    func testLeaveStaysSelectableOnBothChainsThatOfferIt() {
        XCTAssertTrue(FunctionCallType.getCases(for: Self.makeRune()).contains(.leave))
        XCTAssertTrue(FunctionCallType.getCases(for: Self.makeCacao()).contains(.leave))
    }

    /// Kept, narrowed a second time.
    ///
    /// It was the guard on the only entry point there was: the dropdown
    /// applied `getDefault` without publishing a change, so a chain defaulting
    /// to a migrated type opened on a selection that built nothing. Rows carry
    /// their own destination now, so no default decides where a user lands, and
    /// the invariant that protects them is
    /// `FunctionActionCatalogTests.testEveryOfferedActionRoutesToAScreenThatCanBuildIt`
    /// — strictly stronger, covering every operation a chain offers rather than
    /// the one it used to open on.
    ///
    /// The narrowing: a chain whose entry resolves to `.action` never renders
    /// the dropdown at all — the passthrough builds the destination in place —
    /// and its lone case *is* its default, so "the default is migrated" is the
    /// state the action list deliberately made legal rather than a defect. dYdX
    /// is the first chain in it (see
    /// `testASingleActionChainMayDefaultToItsOnlyMigratedOperation`). What
    /// remains guarded is the dropdown that still compiles behind a `.list`.
    func testNoMultiActionChainDefaultsToAMigratedFunction() {
        for chain in Chain.allCases {
            let coin = FunctionCallFixture.makeCoin(
                chain,
                ticker: chain.ticker,
                decimals: 8,
                isNative: true
            )
            guard case .list = FunctionActionCatalog.entry(for: coin) else { continue }

            let defaultType = FunctionCallType.getDefault(for: coin)
            XCTAssertFalse(
                Self.isMigrated(defaultType),
                "\(chain.rawValue) defaults to \(defaultType.rawValue), which no longer builds a form"
            )
        }
    }

    /// The exemption, stated positively rather than left as a hole in the rule
    /// above: dYdX offers exactly one operation, that operation is migrated, and
    /// the entry point therefore opens the migrated screen directly. Its
    /// `getDefault` stays `.vote` because that is honestly the only thing the
    /// chain does — there is nothing unmigrated left to point it at.
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
