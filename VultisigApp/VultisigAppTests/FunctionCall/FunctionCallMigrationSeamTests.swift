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

    /// The function a legacy sub-model instance stands for. Exhaustive on
    /// purpose: `FunctionCallInstance.getDefault` and
    /// `FunctionCallType.getDefault` are two switches that have to agree, and
    /// adding a case to the enum should not compile until this mapping names
    /// it too.
    private static func functionType(of instance: FunctionCallInstance) -> FunctionCallType {
        switch instance {
        case .bondMaya: return .bondMaya
        case .unbondMaya: return .unbondMaya
        case .custom: return .custom
        case .vote: return .vote
        case .cosmosIBC: return .cosmosIBC
        case .merge: return .merge
        case .unmerge: return .unmerge
        case .theSwitch: return .theSwitch
        case .addThorLP: return .addThorLP
        case .securedAsset: return .securedAsset
        case .withdrawSecuredAsset: return .withdrawSecuredAsset
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
            .custom, .vote, .cosmosIBC, .merge, .unmerge,
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
