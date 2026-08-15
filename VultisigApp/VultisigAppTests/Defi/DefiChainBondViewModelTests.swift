//
//  DefiChainBondViewModelTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import SwiftData
import XCTest

@MainActor
final class DefiChainBondViewModelTests: XCTestCase {
    private var storeToken: TestContextToken!
    private var vault: Vault!
    private var interactor: MockBondInteractor!

    override func setUp() async throws {
        try await super.setUp()
        storeToken = try TestStore.installInMemoryContainer()
        vault = TestStore.makeVault()
        interactor = MockBondInteractor()
    }

    override func tearDown() async throws {
        interactor = nil
        vault = nil
        TestStore.restore(storeToken)
        storeToken = nil
        try await super.tearDown()
    }

    // MARK: - Unlisted-node unbond entry

    /// The entry point exists for the user whose node stopped reporting them as
    /// a provider: no active-node card, and therefore no other way into unbond.
    /// So it must not be entangled with holding a position — a gate that reads
    /// `hasBondPositions` anywhere on the path closes the door on exactly the
    /// people it was added for.
    func testMayaOffersUnlistedNodeUnbondWithNoBondPositionsAtAll() async {
        let vm = makeViewModel(chain: .mayaChain)
        await vm.refresh()

        XCTAssertFalse(vm.hasBondPositions, "fixture has no bonds ⇒ the view renders its empty state")
        XCTAssertTrue(
            vm.canUnbondFromUnlistedNode,
            "the unlisted-node entry has to survive the empty state; it is the only route out without a card"
        )
    }

    /// Having a card must not be what turns it on either — the flag tracks the
    /// chain's unbond capability, nothing about the user's positions.
    func testMayaOfferIsUnchangedByHoldingABondPosition() async {
        let cacao = CoinMeta.make(chain: .mayaChain, ticker: "CACAO")
        vault.defiPositions = [DefiPositions(chain: .mayaChain, bonds: [cacao], staking: [], lps: [])]

        let vm = makeViewModel(chain: .mayaChain)
        await vm.refresh()

        XCTAssertTrue(vm.hasBondPositions)
        XCTAssertTrue(vm.canUnbondFromUnlistedNode)
    }

    /// THORChain's unbond validates the amount against the bond the card
    /// carries, so a blank entry point there would be an incomplete flow.
    func testThorchainDoesNotOfferTheUnlistedNodeEntry() async {
        let vm = makeViewModel(chain: .thorChain)
        await vm.refresh()

        XCTAssertTrue(vm.canUnbond)
        XCTAssertFalse(vm.canUnbondFromUnlistedNode)
    }

    /// A chain that cannot unbond at all gets no entry point, empty state or not.
    func testOfferIsWithheldWhenTheChainCannotUnbond() async {
        interactor.canUnbondStub = false
        let vm = makeViewModel(chain: .mayaChain)
        await vm.refresh()

        XCTAssertFalse(vm.canUnbondFromUnlistedNode)
    }

    // MARK: - Helpers

    private func makeViewModel(chain: Chain) -> DefiChainBondViewModel {
        DefiChainBondViewModel(vault: vault, chain: chain, interactor: interactor)
    }
}
