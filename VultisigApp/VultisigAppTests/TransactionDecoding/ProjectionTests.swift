//
//  ProjectionTests.swift
//  VultisigAppTests
//

import BigInt
@testable import VultisigApp
import XCTest

final class ProjectionTests: XCTestCase {

    // MARK: - Signed query key

    /// Query subjects must come from signed content.
    func testAKeyCannotBeBuiltWithoutASignedCounterparty() {
        let noCounterparty = DecodedTransaction(
            operation: .unstake, amount: .unstated, counterparty: nil, evidence: .signedData
        )
        XCTAssertNil(ProjectionQueryKey(noCounterparty))

        let named = DecodedTransaction(
            operation: .unstake, amount: .unstated,
            counterparty: .validator("StakeAccount111"), evidence: .signedData
        )
        XCTAssertEqual(ProjectionQueryKey(named)?.counterparty, .validator("StakeAccount111"))
    }

    // MARK: - The scope is the floor

    func testAWholePositionUnstakeStatesItsScope() {
        let decoded = DecodedTransaction(
            operation: .unstake, amount: .unstated, evidence: .signedData
        )
        XCTAssertEqual(ProjectionCoordinator.scope(for: decoded), "scopeYourWholeStake".localized)
    }

    func testAFractionStatesTheShareItCommitsTo() throws {
        let decoded = DecodedTransaction(
            operation: .unstake, amount: .fraction(basisPoints: 5006, of: .transactionCoin), evidence: .memo
        )
        let scope = try XCTUnwrap(ProjectionCoordinator.scope(for: decoded))
        XCTAssertTrue(scope.contains("50.06"), "the committed share should be stated exactly: \(scope)")
    }

    /// Committed amounts are not projections.
    func testACommittedAmountIsNeverAProjection() {
        let committed = DecodedTransaction(
            operation: .stake, amount: .units(BigInt(1), of: .chainNative), evidence: .memo
        )
        XCTAssertNil(ProjectionCoordinator.scope(for: committed))
        XCTAssertNil(ProjectionCoordinator.hero(for: committed, title: "You’re staking"))
    }

    /// The hero renders from the decoding alone — nothing is awaited to produce it.
    func testTheScopeRendersWithoutAnEstimate() throws {
        let decoded = DecodedTransaction(
            operation: .unstake, amount: .unstated, evidence: .signedData
        )
        let hero = try XCTUnwrap(ProjectionCoordinator.hero(for: decoded, title: "You’re unstaking"))
        guard case .projected(let title, let estimate, let scope) = hero else {
            return XCTFail("an unsettled quantity must render as a projection")
        }
        XCTAssertEqual(title, "You’re unstaking")
        XCTAssertNil(estimate, "the verb and scope must not wait for a read")
        XCTAssertFalse(scope.isEmpty)
    }

    // MARK: - Every failure lands in the same place

    func testASuccessfulReadBecomesTheEstimate() async {
        let estimate = await ProjectionCoordinator.estimate(
            for: Self.unstakeOfAStakeAccount,
            using: [StubResolver(result: Self.twelveSol)]
        )
        XCTAssertEqual(estimate, Self.twelveSol)
    }

    func testAFailedReadLeavesNoEstimate() async {
        let estimate = await ProjectionCoordinator.estimate(
            for: Self.unstakeOfAStakeAccount, using: [StubResolver(result: nil)]
        )
        XCTAssertNil(estimate)
    }

    func testDecodedHeroStatesProjectionScopeBeforeAnyRead() throws {
        let decoded = DecodedTransaction(operation: .unstake, amount: .unstated, evidence: .signedData)
        let coin = Coin(
            asset: CoinMeta(
                chain: .thorChain, ticker: "RUNE", logo: "rune", decimals: 8,
                priceProviderId: "thorchain", contractAddress: "", isNativeToken: true
            ),
            address: "thor1owner", hexPublicKey: "hex"
        )
        let hero = try XCTUnwrap(DecodedTransactionPresentation.hero(for: decoded, coin: coin))
        guard case .projected(_, let estimate, let scope) = hero else {
            return XCTFail("the synchronous decoder hero must state the projection scope")
        }
        XCTAssertNil(estimate)
        XCTAssertEqual(scope, "scopeYourWholeStake".localized)
    }

    /// Slow optional reads degrade to scope-only presentation.
    func testASlowReadTimesOutRatherThanHangingTheScreen() async {
        let estimate = await ProjectionCoordinator.estimate(
            for: Self.unstakeOfAStakeAccount,
            using: [StubResolver(result: Self.twelveSol, delay: .seconds(30))]
        )
        XCTAssertNil(estimate, "a slow read must degrade to the scope, not delay the hero")
    }

    /// The deadline must hold when the resolver ignores cancellation.
    func testTheDeadlineHoldsEvenIfTheResolverIgnoresCancellation() async {
        let started = ContinuousClock.now
        let estimate = await ProjectionCoordinator.estimate(
            for: Self.unstakeOfAStakeAccount,
            using: [UncancellableResolver()]
        )
        let elapsed = ContinuousClock.now - started

        XCTAssertNil(estimate)
        XCTAssertLessThan(
            elapsed, .seconds(15),
            "the screen waited \(elapsed) on a resolver that never yields — the deadline is not being enforced"
        )
    }

    func testAnUnhandledOperationAsksNobody() async {
        let estimate = await ProjectionCoordinator.estimate(
            for: Self.unstakeOfAStakeAccount,
            using: [StubResolver(result: Self.twelveSol, handles: .stake)]
        )
        XCTAssertNil(estimate)
    }

    // MARK: - Fixtures

    private static let twelveSol = HeroCoinAmount(amount: "12.5", ticker: "SOL", logo: "solana")

    private static let unstakeOfAStakeAccount = DecodedTransaction(
        operation: .unstake, amount: .unstated,
        counterparty: .validator("StakeAccount111"), evidence: .signedData
    )

    /// Models a client governed by its own timeout.
    private struct UncancellableResolver: ProjectionResolving {
        func handles(_: DecodedOperation) -> Bool { true }

        func projection(for _: DecodedTransaction, key _: ProjectionQueryKey) async -> HeroCoinAmount? {
            let deadline = ContinuousClock.now + .seconds(60)
            while ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(50))
            }
            return HeroCoinAmount(amount: "1", ticker: "SOL", logo: "solana")
        }
    }

    private struct StubResolver: ProjectionResolving {
        let result: HeroCoinAmount?
        var delay: Duration = .zero
        var handles: DecodedOperation = .unstake

        func handles(_ operation: DecodedOperation) -> Bool { operation == handles }

        func projection(for _: DecodedTransaction, key _: ProjectionQueryKey) async -> HeroCoinAmount? {
            if delay > .zero { try? await Task.sleep(for: delay) }
            return result
        }
    }
}
