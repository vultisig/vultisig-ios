//
//  FunctionActionCatalogTests.swift
//  VultisigAppTests
//
//  The action list replaced a dropdown whose default selection was the source
//  of a recurring class of defect: a chain opening on a form its own dropdown
//  never offered. These pin the two properties that make the replacement an
//  improvement rather than a reshuffle —
//
//  1. every operation a chain offers becomes a row that lands on a screen able
//     to build it (nothing is stranded, nothing is unreachable), and
//  2. a chain with exactly one operation skips the list, *including* when that
//     one operation has already been migrated — the case the old
//     selection-change seam could not express at all, because a lone case is
//     also its chain's default and a default never publishes a change.
//

@testable import VultisigApp
import XCTest

final class FunctionActionCatalogTests: XCTestCase {

    private static func makeCoin(_ chain: Chain) -> Coin {
        FunctionCallFixture.makeCoin(
            chain,
            ticker: chain.ticker,
            decimals: 8,
            isNative: true
        )
    }

    /// Chains that surface the Functions entry button.
    private var entryChains: [Chain] { CoinAction.memoChains }

    // MARK: - The descriptor set per chain

    func testDescriptorsMirrorTheChainsCaseListInOrder() {
        for chain in entryChains {
            let coin = Self.makeCoin(chain)
            let types = FunctionCallType.getCases(for: coin)
            let descriptors = FunctionActionCatalog.descriptors(for: coin)

            XCTAssertEqual(
                descriptors.map { $0.id },
                types.map { $0.rawValue },
                "\(chain.rawValue) must offer exactly the operations its case list names, in order"
            )
        }
    }

    /// A chain that shows the entry button and offers nothing behind it is a
    /// button that leads to an empty screen — which is what THORChain
    /// chainnet/stagenet did.
    func testEveryChainWithTheEntryButtonOffersAtLeastOneAction() {
        for chain in entryChains {
            XCTAssertFalse(
                FunctionActionCatalog.descriptors(for: Self.makeCoin(chain)).isEmpty,
                "\(chain.rawValue) offers the Functions button with no operation behind it"
            )
        }
    }

    /// The invariant the list exists to guarantee, and the one that supersedes
    /// "no chain defaults to a migrated function": whatever a row names, the
    /// screen it opens can build it. A migrated operation goes to its own
    /// screen; an unmigrated one opens the legacy form *pre-selected to that
    /// same operation*, never to a default.
    ///
    /// "Can build it" reduces to `migratedTransactionType == nil` because the
    /// legacy screen's form factory has exactly one non-building arm — the
    /// migrated set, which each migration adds its case name to. A row that is
    /// unmigrated therefore has a form waiting for it.
    func testEveryOfferedActionRoutesToAScreenThatCanBuildIt() {
        for chain in entryChains {
            let coin = Self.makeCoin(chain)

            for descriptor in FunctionActionCatalog.descriptors(for: coin) {
                guard let type = FunctionCallType(rawValue: descriptor.id) else {
                    return XCTFail("\(descriptor.id) is not a function type")
                }
                let migrated = type.migratedTransactionType(coin: coin, nodeAddress: nil)

                switch descriptor.destination {
                case .transaction:
                    XCTAssertNotNil(
                        migrated,
                        "\(chain.rawValue)/\(type.rawValue) routes to a transaction screen it has not been migrated to"
                    )
                case .legacyFunctionCall(let preselected):
                    XCTAssertEqual(
                        preselected,
                        type,
                        "\(chain.rawValue) opens the legacy form on \(preselected.rawValue) from the \(type.rawValue) row"
                    )
                    XCTAssertNil(
                        migrated,
                        "\(type.rawValue) is migrated and no longer builds a legacy form"
                    )
                }
            }
        }
    }

    func testDescriptorsCarryCopyForEveryOperation() {
        for type in FunctionCallType.allCases {
            let descriptor = type.actionDescriptor(for: Self.makeCoin(.thorChain))
            XCTAssertFalse(descriptor.title.isEmpty, "\(type.rawValue) has no title")
            XCTAssertFalse(
                descriptor.subtitle?.isEmpty ?? true,
                "\(type.rawValue) has no subtitle — the dropdown could only show a name, the list explains"
            )
            XCTAssertTrue(descriptor.isAvailable)
        }
    }

    // MARK: - Single-action passthrough

    /// Replaces `testASingleActionSkipsTheList`, which used dYdX as its
    /// one-action chain back when the vote was still legacy: dYdX is now the
    /// first *real* instance of the shape the synthetic test below describes —
    /// one action, already migrated. The unmigrated single-action case is still
    /// covered, by `testThorchainTestNetworksPassThroughToCustom`.
    ///
    /// This is the only way into the governance vote, so a fall-back to the
    /// legacy screen would open a form that no longer exists.
    func testDydxPassesThroughToTheMigratedVoteScreen() {
        let coin = Self.makeCoin(.dydx)
        XCTAssertEqual(FunctionCallType.getCases(for: coin), [.vote], "dYdX must offer exactly the vote")

        guard case .action(let descriptor) = FunctionActionCatalog.entry(for: coin) else {
            return XCTFail("A chain with one action must open that action directly")
        }
        guard case .transaction(let transactionType) = descriptor.destination else {
            return XCTFail("dYdX's vote is migrated and must not be routed through the legacy screen")
        }
        guard case .dydxVote(let voteCoin) = transactionType else {
            return XCTFail("Expected the dYdX vote intent")
        }
        XCTAssertEqual(voteCoin.chain, .dydx)
        XCTAssertEqual(voteCoin.ticker, "DYDX")
        XCTAssertTrue(voteCoin.isNativeToken)

        // And the route the descriptor names really is the transaction screen —
        // no default, no legacy screen, nothing between the entry button and the
        // ballot.
        let vault = FunctionCallFixture.makeVault(coins: [coin])
        guard case .functionTransaction(_, let routed) = FunctionCallRoute.route(
            for: descriptor.destination,
            coin: coin,
            vault: vault
        ) else {
            return XCTFail("dYdX's single action must route to FunctionTransactionScreen")
        }
        XCTAssertEqual(routed, transactionType)
    }

    /// The constraint this screen removes.
    ///
    /// Before the list, a migrated operation was reached by *changing* the
    /// dropdown selection, so a chain whose only operation was migrated could
    /// never route out: its lone case is also its default, and the default is
    /// applied without publishing a change. That blocked migrating `vote`,
    /// `cosmosIBC` and `addThorLP`, and would eventually have blocked the last
    /// operation on THORChain and MayaChain.
    ///
    /// Built from an explicit case list rather than a chain's, because the
    /// point is the shape — one action, already migrated — not which chain
    /// happens to have it while the sibling migrations land.
    func testASingleMigratedActionRoutesStraightToItsOwnScreen() {
        let coin = FunctionCallFixture.makeRUNE()
        let descriptors = FunctionActionCatalog.descriptors(for: coin, types: [.leave])

        guard case .action(let descriptor) = FunctionActionCatalog.entry(descriptors: descriptors) else {
            return XCTFail("A chain whose only action is migrated must open that action directly")
        }
        guard case .transaction(let transactionType) = descriptor.destination else {
            return XCTFail("A migrated action must not be routed through the legacy screen")
        }
        guard case .leave(let leaveCoin, let node) = transactionType else {
            return XCTFail("Expected the leave intent")
        }

        XCTAssertEqual(leaveCoin.chain, .thorChain)
        XCTAssertEqual(leaveCoin.ticker, "RUNE")
        XCTAssertNil(node, "The list is entered cold — there is no previous form to inherit a node address from")
    }

    func testMoreThanOneActionRendersTheList() {
        let coin = FunctionCallFixture.makeRUNE()
        let expected = FunctionCallType.getCases(for: coin)
        XCTAssertGreaterThan(expected.count, 1, "Fixture chain must offer several actions")

        guard case .list(let descriptors) = FunctionActionCatalog.entry(for: coin) else {
            return XCTFail("A chain with several actions must show the list")
        }
        XCTAssertEqual(descriptors.map { $0.id }, expected.map { $0.rawValue })
    }

    func testNoActionsStillRendersTheList() {
        // Not reachable from the UI (pinned above), but the entry point must
        // not fall through to a screen it cannot name.
        guard case .list(let descriptors) = FunctionActionCatalog.entry(for: Self.makeCoin(.solana)) else {
            return XCTFail("A chain with no actions must not resolve to an action")
        }
        XCTAssertTrue(descriptors.isEmpty)
    }

    /// The test networks offered the entry button over an empty selector.
    /// They now pass through to the one operation they support.
    func testThorchainTestNetworksPassThroughToCustom() {
        for chain in [Chain.thorChainChainnet, Chain.thorChainStagenet] {
            guard case .action(let descriptor) = FunctionActionCatalog.entry(for: Self.makeCoin(chain)) else {
                return XCTFail("\(chain.rawValue) must open its single action directly")
            }
            XCTAssertEqual(descriptor.destination, .legacyFunctionCall(.custom))
        }
    }

    // MARK: - Destination → route

    func testAMigratedDestinationRoutesToItsTransactionScreen() {
        let coin = FunctionCallFixture.makeRUNE()
        let vault = FunctionCallFixture.makeVault(coins: [coin])
        let intent = FunctionTransactionType.leave(coin: coin.toCoinMeta(), node: nil)

        guard case .functionTransaction(_, let transactionType) = FunctionCallRoute.route(
            for: .transaction(intent),
            coin: coin,
            vault: vault
        ) else {
            return XCTFail("A migrated destination must open FunctionTransactionScreen")
        }
        XCTAssertEqual(transactionType, intent)
    }

    /// The legacy screen is reached *pre-selected*, which is what lets it hide
    /// both selectors: the row already made the choice the dropdown asked for.
    func testALegacyDestinationRoutesToTheFormPreselectedToThatFunction() {
        let coin = FunctionCallFixture.makeRUNE()
        let vault = FunctionCallFixture.makeVault(coins: [coin])

        guard case .details(let defaultCoin, _, let preselected) = FunctionCallRoute.route(
            for: .legacyFunctionCall(.merge),
            coin: coin,
            vault: vault
        ) else {
            return XCTFail("An unmigrated destination must open the legacy form")
        }
        XCTAssertEqual(preselected, .merge)
        XCTAssertEqual(defaultCoin, coin)
    }

    // MARK: - Coin resolution

    func testTheEntryCoinFallsBackToTheVaultsNativeCoin() {
        let rune = FunctionCallFixture.makeRUNE()
        let tcy = FunctionCallFixture.makeTCY()
        let vault = FunctionCallFixture.makeVault(coins: [tcy, rune])

        XCTAssertEqual(FunctionActionCatalog.resolveCoin(defaultCoin: tcy, vault: vault), tcy)
        XCTAssertEqual(FunctionActionCatalog.resolveCoin(defaultCoin: nil, vault: vault), rune)
    }
}
