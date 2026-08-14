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
        FunctionActionFixture.makeCoin(
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
            let types = FunctionAction.offered(on: coin)
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

    /// The invariant the list exists to guarantee, and the one that superseded
    /// "no chain defaults to a migrated function": whatever a row names, the
    /// router can build it.
    ///
    /// It used to have to allow for two kinds of destination, one of which was
    /// a form on the legacy screen. Every operation has its own screen now, so
    /// what is left to pin is that a row's destination is *the mapping's own
    /// answer for that operation and that coin* — not a stale copy taken when
    /// the descriptor was built, and not another operation's intent.
    func testEveryOfferedActionRoutesToTheIntentItsOperationNames() {
        for chain in entryChains {
            let coin = Self.makeCoin(chain)

            for descriptor in FunctionActionCatalog.descriptors(for: coin) {
                guard let action = FunctionAction(rawValue: descriptor.id) else {
                    return XCTFail("\(descriptor.id) is not an operation")
                }
                XCTAssertEqual(
                    descriptor.destination,
                    action.transactionType(coin: coin),
                    "\(chain.rawValue)/\(action.rawValue) routes somewhere its own mapping does not name"
                )
            }
        }
    }

    func testDescriptorsCarryCopyForEveryOperation() {
        for type in FunctionAction.allCases {
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
        XCTAssertEqual(FunctionAction.offered(on: coin), [.vote], "dYdX must offer exactly the vote")

        guard case .action(let descriptor) = FunctionActionCatalog.entry(for: coin) else {
            return XCTFail("A chain with one action must open that action directly")
        }
        let transactionType = descriptor.destination
        guard case .dydxVote(let voteCoin) = transactionType else {
            return XCTFail("Expected the dYdX vote intent")
        }
        XCTAssertEqual(voteCoin.chain, .dydx)
        XCTAssertEqual(voteCoin.ticker, "DYDX")
        XCTAssertTrue(voteCoin.isNativeToken)

        // And the route the descriptor names really is the transaction screen —
        // no default, no legacy screen, nothing between the entry button and the
        // ballot.
        let vault = FunctionActionFixture.makeVault(coins: [coin])
        guard case .functionTransaction(_, let routed) = FunctionTransactionRoute.route(
            for: descriptor.destination,
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
        let coin = FunctionActionFixture.makeRUNE()
        let descriptors = FunctionActionCatalog.descriptors(for: coin, types: [.leave])

        guard case .action(let descriptor) = FunctionActionCatalog.entry(descriptors: descriptors) else {
            return XCTFail("A chain whose only action is migrated must open that action directly")
        }
        guard case .leave(let leaveCoin, let node) = descriptor.destination else {
            return XCTFail("Expected the leave intent")
        }

        XCTAssertEqual(leaveCoin.chain, .thorChain)
        XCTAssertEqual(leaveCoin.ticker, "RUNE")
        XCTAssertNil(node, "The list is entered cold — there is no previous form to inherit a node address from")
    }

    /// The constraint made concrete. Kujira and Osmosis each offer exactly one
    /// operation and that operation is now migrated — the shape
    /// `testASingleMigratedActionRoutesStraightToItsOwnScreen` describes with a
    /// synthetic case list, here on the real chains that have it. Under the
    /// selection-change seam these two were unmigratable: a lone case is also
    /// the chain's default, and a default never publishes a change.
    func testTheSingleActionChainsPassThroughToTheIbcScreen() {
        for chain in [Chain.kujira, Chain.osmosis] {
            let coin = Self.makeCoin(chain)
            XCTAssertEqual(
                FunctionAction.offered(on: coin),
                [.cosmosIBC],
                "\(chain.rawValue) must offer IBC and nothing else for this to be the passthrough case"
            )

            guard case .action(let descriptor) = FunctionActionCatalog.entry(for: coin) else {
                return XCTFail("\(chain.rawValue) must open its single action directly, not via the list")
            }
            guard case .ibcTransfer(let intentCoin, let destination) = descriptor.destination else {
                return XCTFail("Expected the IBC transfer intent on \(chain.rawValue)")
            }

            XCTAssertEqual(intentCoin.chain, chain)
            XCTAssertNil(destination, "The list is entered cold — there is no route to inherit")
        }
    }

    /// Gaia offers two operations, so it renders the list, and each row names
    /// the intent its own screen is built from. Gaia is the chain the epic's
    /// two Cosmos migrations met on — SWITCH re-pointed its default, IBC then
    /// took the operation that default named — so it is the one worth pinning
    /// row-by-row.
    func testGaiaRendersAListOfBothItsOperations() {
        let coin = Self.makeCoin(.gaiaChain)

        guard case .list(let descriptors) = FunctionActionCatalog.entry(for: coin) else {
            return XCTFail("Gaia offers two operations and must show the list")
        }
        XCTAssertEqual(descriptors.map { $0.id }, [FunctionAction.cosmosIBC.rawValue, FunctionAction.theSwitch.rawValue])

        guard case .ibcTransfer(let intentCoin, _) = descriptors[0].destination else {
            return XCTFail("Expected the IBC transfer intent")
        }
        XCTAssertEqual(intentCoin.chain, .gaiaChain)

        guard case .theSwitch(let switchCoin) = descriptors[1].destination else {
            return XCTFail("Gaia's Switch row must route to the migrated screen")
        }
        // The chain's own asset as the token store knows it, not the fixture
        // coin: SWITCH credits only the native asset on the inbound vault.
        XCTAssertEqual(switchCoin.chain, .gaiaChain)
        XCTAssertTrue(switchCoin.isNativeToken)
    }

    func testMoreThanOneActionRendersTheList() {
        let coin = FunctionActionFixture.makeRUNE()
        let expected = FunctionAction.offered(on: coin)
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
    /// They now pass through to the one operation they support — which is also
    /// the case the previous selection-change seam could not express at all,
    /// since a lone case is its chain's default and a default publishes no
    /// change.
    func testThorchainTestNetworksPassThroughToCustom() {
        for chain in [Chain.thorChainChainnet, Chain.thorChainStagenet] {
            let coin = Self.makeCoin(chain)
            guard case .action(let descriptor) = FunctionActionCatalog.entry(for: coin) else {
                return XCTFail("\(chain.rawValue) must open its single action directly")
            }
            XCTAssertEqual(
                descriptor.destination,
                .customMemo(coin: coin.toCoinMeta()),
                "\(chain.rawValue) must open the raw-memo form on the coin it was entered from"
            )
        }
    }

    // MARK: - Destination → route

    func testAMigratedDestinationRoutesToItsTransactionScreen() {
        let coin = FunctionActionFixture.makeRUNE()
        let vault = FunctionActionFixture.makeVault(coins: [coin])
        let intent = FunctionTransactionType.leave(coin: coin.toCoinMeta(), node: nil)

        guard case .functionTransaction(_, let transactionType) = FunctionTransactionRoute.route(
            for: intent,
            vault: vault
        ) else {
            return XCTFail("A migrated destination must open FunctionTransactionScreen")
        }
        XCTAssertEqual(transactionType, intent)
    }

    // MARK: - Coin resolution

    func testTheEntryCoinFallsBackToTheVaultsNativeCoin() {
        let rune = FunctionActionFixture.makeRUNE()
        let tcy = FunctionActionFixture.makeTCY()
        let vault = FunctionActionFixture.makeVault(coins: [tcy, rune])

        XCTAssertEqual(FunctionActionCatalog.resolveCoin(defaultCoin: tcy, vault: vault), tcy)
        XCTAssertEqual(FunctionActionCatalog.resolveCoin(defaultCoin: nil, vault: vault), rune)
    }
}
