//
//  MayaCacaoStakingPreflightTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

@MainActor
final class MayaCacaoStakingPreflightTests: XCTestCase {
    func testHaltedNetworkBlocksStakeAndUnstake() async {
        let preflight = MayaCacaoStakingPreflight { .halted }
        let builders: [TransactionBuilder] = [
            CacaoStakeTransactionBuilder(coin: .example, amount: "1"),
            CacaoUnstakeTransactionBuilder(coin: .example, bps: 5_000)
        ]

        for builder in builders {
            do {
                try await preflight.validate(builder)
                XCTFail("A halted MAYAChain must block every CACAO pool action.")
            } catch let error as MayaCacaoStakingPreflightError {
                XCTAssertEqual(error, .halted)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testAvailableNetworkAllowsStakeAndUnstake() async throws {
        let preflight = MayaCacaoStakingPreflight { .available }

        try await preflight.validate(CacaoStakeTransactionBuilder(coin: .example, amount: "1"))
        try await preflight.validate(CacaoUnstakeTransactionBuilder(coin: .example, bps: 5_000))
    }

    func testAvailabilityFailureBlocksSigningAsUnavailable() async {
        let preflight = MayaCacaoStakingPreflight { throw StubError.unreachable }

        do {
            try await preflight.validate(CacaoStakeTransactionBuilder(coin: .example, amount: "1"))
            XCTFail("An unverifiable network state must fail closed.")
        } catch let error as MayaCacaoStakingPreflightError {
            XCTAssertEqual(error, .unavailable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUnrelatedTransactionSkipsAvailabilityRequest() async throws {
        var requestCount = 0
        let preflight = MayaCacaoStakingPreflight {
            requestCount += 1
            return .halted
        }
        let builder = CustomMemoTransactionBuilder(
            coin: .example,
            customMemo: "memo",
            customAmount: 0
        )

        try await preflight.validate(builder)

        XCTAssertEqual(requestCount, 0)
    }
}

private enum StubError: Error {
    case unreachable
}
