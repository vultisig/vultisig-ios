//
//  UnstakeRoutingTests.swift
//  VultisigAppTests
//
//  The unstake sheet's ceiling comes from the position, and the position states
//  it. It is not the route's job to infer one: a route that guessed from the
//  position's size would be right only where the two happen to coincide, and
//  where it guessed nothing the sheet fell through to `coin.stakedBalanceDecimal`
//  — a figure `BalanceService` maintains on its own refresh cycle, independent of
//  the DeFi read the card was drawn from. That is how a card showing a real stake
//  opened a sheet offering nothing.
//

@testable import VultisigApp
import XCTest

@MainActor
final class UnstakeRoutingTests: XCTestCase {

    private var token: TestContextToken?

    override func setUpWithError() throws {
        token = try TestStore.installInMemoryContainer()
    }

    override func tearDown() {
        TestStore.restore(token)
        token = nil
        super.tearDown()
    }

    /// The ceiling the route hands the sheet. Double-optional so "not an unstake
    /// route" stays distinguishable from "unstake with no ceiling".
    private func routedCeiling(_ type: FunctionTransactionType?) -> Decimal?? {
        guard case .unstake(_, _, let available) = type else { return nil }
        return .some(available)
    }

    private func makeModel(vault: Vault) -> DefiChainScreenModel {
        DefiChainScreenModel(vault: vault, chain: .thorChain)
    }

    private func makePosition(
        vault: Vault,
        coin: CoinMeta = TokensStore.tcy,
        type: StakePositionType = .stake,
        amount: Decimal,
        availableToUnstake: Decimal?
    ) -> StakePosition {
        StakePosition(
            coin: coin,
            type: type,
            amount: amount,
            availableToUnstake: availableToUnstake,
            vault: vault
        )
    }

    // MARK: - The route passes the stated ceiling through

    func testBondedPositionRoutesTheStatedCeiling() throws {
        let vault = TestStore.makeVault(pubKey: "unstake-bonded")
        let position = makePosition(vault: vault, amount: 12.5, availableToUnstake: 12.5)

        let ceiling = try XCTUnwrap(routedCeiling(makeModel(vault: vault).unstakeTransactionType(for: position)))

        XCTAssertEqual(ceiling, 12.5)
    }

    func testCompoundPositionRoutesTheStatedCeiling() throws {
        let vault = TestStore.makeVault(pubKey: "unstake-compound")
        let position = makePosition(
            vault: vault,
            coin: TokensStore.stcy,
            type: .compound,
            amount: 7,
            availableToUnstake: 7
        )

        guard case .unstake(_, let isAutocompound, let available) =
                makeModel(vault: vault).unstakeTransactionType(for: position) else {
            return XCTFail("expected an unstake route")
        }

        XCTAssertTrue(isAutocompound)
        XCTAssertEqual(available, 7)
    }

    /// A ceiling that differs from the position's size survives — the whole
    /// reason it is stated separately. Maya is the standing case: the card shows
    /// the member's CACAO value and the sheet has to type against that same
    /// value rather than the pool units underneath it.
    func testACeilingThatDiffersFromTheAmountIsNotOverwritten() throws {
        let vault = TestStore.makeVault(pubKey: "unstake-distinct")
        let position = makePosition(vault: vault, amount: 10, availableToUnstake: 3)

        let ceiling = try XCTUnwrap(routedCeiling(makeModel(vault: vault).unstakeTransactionType(for: position)))

        XCTAssertEqual(ceiling, 3, "the route must not substitute the position's size for the stated ceiling")
    }

    func testAnEmptyPositionRoutesZero() throws {
        let vault = TestStore.makeVault(pubKey: "unstake-empty")
        let position = makePosition(vault: vault, amount: 0, availableToUnstake: 0)

        XCTAssertFalse(position.canUnstake, "an empty position does not offer Unstake")

        let ceiling = try XCTUnwrap(routedCeiling(makeModel(vault: vault).unstakeTransactionType(for: position)))
        XCTAssertEqual(ceiling, 0)
    }

    /// Rows persisted before the ceiling was required still carry `nil`, and the
    /// route passes that on rather than inventing a figure. They are corrected by
    /// the first refresh, which writes a ceiling the producer stated. Pinned so
    /// the behaviour is a decision on record rather than an accident.
    func testAPersistedRowWithNoStatedCeilingRoutesNil() throws {
        let vault = TestStore.makeVault(pubKey: "unstake-legacy")
        let position = makePosition(vault: vault, amount: 9, availableToUnstake: nil)

        let ceiling = try XCTUnwrap(routedCeiling(makeModel(vault: vault).unstakeTransactionType(for: position)))

        XCTAssertNil(ceiling)
    }
}
