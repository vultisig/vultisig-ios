//
//  UnstakeRoutingTests.swift
//  VultisigAppTests
//
//  The DeFi card and the unstake sheet it opens must agree about how much there
//  is to unstake. They read the number from different places — the card from the
//  position the DeFi interactor produced, the sheet from whatever the route
//  hands it — and when the route handed over nothing the sheet fell through to
//  `coin.stakedBalanceDecimal`, a field on `BalanceService`'s refresh cycle
//  rather than the DeFi read. THORChain's interactor sets no explicit ceiling,
//  so its bonded positions opened an empty sheet from a card showing a real
//  stake.
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

    /// The ceiling the route hands the sheet, or `nil` if this isn't an unstake.
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
        availableToUnstake: Decimal? = nil
    ) -> StakePosition {
        StakePosition(
            coin: coin,
            type: type,
            amount: amount,
            availableToUnstake: availableToUnstake,
            vault: vault
        )
    }

    // MARK: - The reported bug

    /// THORChain's interactor reports `amount` and never `availableToUnstake`,
    /// so the route has to fall back to it rather than passing nil on.
    func testBondedPositionRoutesThePositionAmount() throws {
        let vault = TestStore.makeVault(pubKey: "unstake-bonded")
        let position = makePosition(vault: vault, amount: 12.5)

        let ceiling = try XCTUnwrap(routedCeiling(makeModel(vault: vault).unstakeTransactionType(for: position)))

        XCTAssertEqual(ceiling, 12.5, "the sheet must open against the amount the card displayed")
    }

    /// The invariant behind the bug, stated as itself: the card's Unstake button
    /// is gated on `canUnstake`, which reads `availableToUnstake ?? amount`. If
    /// the route resolved that differently, the button would be live and the
    /// sheet empty — which is exactly what users saw.
    func testACardThatOffersUnstakeAlwaysOpensANonZeroSheet() throws {
        let vault = TestStore.makeVault(pubKey: "unstake-invariant")

        for (amount, available) in [(Decimal(9), nil as Decimal?), (Decimal(9), Decimal(4)), (Decimal(0.00000001), nil)] {
            let position = makePosition(vault: vault, amount: amount, availableToUnstake: available)
            XCTAssertTrue(position.canUnstake, "precondition: the card offers Unstake here")

            let ceiling = try XCTUnwrap(routedCeiling(makeModel(vault: vault).unstakeTransactionType(for: position)))
            let resolved = try XCTUnwrap(ceiling, "the route must not hand the sheet a nil ceiling")

            XCTAssertGreaterThan(resolved, 0, "amount \(amount), available \(String(describing: available))")
        }
    }

    /// An interactor that does distinguish the two still wins — Maya sets
    /// `availableToUnstake` deliberately, and the fallback must not overwrite it.
    func testAnExplicitCeilingStillWins() throws {
        let vault = TestStore.makeVault(pubKey: "unstake-explicit")
        let position = makePosition(vault: vault, amount: 10, availableToUnstake: 3)

        let ceiling = try XCTUnwrap(routedCeiling(makeModel(vault: vault).unstakeTransactionType(for: position)))

        XCTAssertEqual(ceiling, 3, "an explicit ceiling is not the position's size and must survive")
    }

    /// A genuinely empty position still routes zero rather than being papered
    /// over — the sheet's own guard is what should refuse, not a made-up figure.
    func testAnEmptyPositionStillRoutesZero() throws {
        let vault = TestStore.makeVault(pubKey: "unstake-empty")
        let position = makePosition(vault: vault, amount: 0)

        XCTAssertFalse(position.canUnstake, "an empty position does not offer Unstake")

        let ceiling = try XCTUnwrap(routedCeiling(makeModel(vault: vault).unstakeTransactionType(for: position)))
        XCTAssertEqual(ceiling, 0)
    }

    // MARK: - The branch that already worked

    func testCompoundPositionIsUnchanged() throws {
        let vault = TestStore.makeVault(pubKey: "unstake-compound")
        let position = makePosition(vault: vault, coin: TokensStore.stcy, type: .compound, amount: 7)

        guard case .unstake(_, let isAutocompound, let available) =
                makeModel(vault: vault).unstakeTransactionType(for: position) else {
            return XCTFail("expected an unstake route")
        }

        XCTAssertTrue(isAutocompound)
        XCTAssertEqual(available, 7, "the compound branch already passed the position's amount")
    }
}
