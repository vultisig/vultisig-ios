//
//  StubERC20ApprovalResolver.swift
//  VultisigAppTests
//

import BigInt
import XCTest
@testable import VultisigApp

/// Answers every approval query with one fixed requirement (or error) and
/// records what was asked, so builder tests never reach a node.
final class StubERC20ApprovalResolver: ERC20ApprovalResolving {
    private(set) var queries: [ERC20ApprovalQuery] = []
    private let result: Result<ERC20ApprovalRequirement, Error>

    init(_ requirement: ERC20ApprovalRequirement) {
        result = .success(requirement)
    }

    init(error: Error) {
        result = .failure(error)
    }

    // swiftlint:disable:next async_without_await
    func requirement(for query: ERC20ApprovalQuery) async throws -> ERC20ApprovalRequirement {
        queries.append(query)
        return try result.get()
    }
}

/// Fails the test if any approval is resolved: for routes that must never
/// read an allowance.
final class UnexpectedERC20ApprovalResolver: ERC20ApprovalResolving {
    // swiftlint:disable:next async_without_await
    func requirement(for query: ERC20ApprovalQuery) async throws -> ERC20ApprovalRequirement {
        XCTFail("Unexpected allowance read for \(query.token) on \(query.chain)")
        throw URLError(.unknown)
    }
}

extension SwapInteractor {
    // swiftlint:disable async_without_await
    /// Test-seam default for the swap interactor mocks: the swap signs no
    /// approve. `DefaultSwapInteractor` implements it against the chain, and
    /// this default is visible to the test target only.
    func resolveApproval(for _: SwapTransaction, vault _: Vault) async throws -> ERC20ApprovalDecision? {
        nil
    }
    // swiftlint:enable async_without_await
}

extension SwapTransaction {
    /// The market transaction as the hand-off into Verify leaves it: carrying
    /// `requirement` for the spend its quote approves, or no decision when the
    /// source approves nothing.
    @MainActor
    func withApprovalDecided(_ requirement: ERC20ApprovalRequirement) throws -> SwapTransaction {
        let query = try SwapCryptoLogic.approvalQuery(fromCoin: fromCoin, amount: amountInCoinDecimal, quote: quote)
        return with(approvalDecision: query.map { ERC20ApprovalDecision(query: $0, requirement: requirement) })
    }
}

// swiftlint:disable async_without_await unused_parameter
/// A `SwapInteractor` that only answers the approval read; everything else is
/// inert. For hand-offs that read the approval before Verify.
final class ApprovalReadingSwapInteractor: SwapInteractor {
    private let result: Result<ERC20ApprovalDecision?, Error>
    private(set) var resolveApprovalCallCount = 0

    init(decision: ERC20ApprovalDecision?) {
        result = .success(decision)
    }

    init(error: Error) {
        result = .failure(error)
    }

    func resolveApproval(for transaction: SwapTransaction, vault: Vault) async throws -> ERC20ApprovalDecision? {
        resolveApprovalCallCount += 1
        return try result.get()
    }

    func fetchQuote(
        amount: Decimal,
        fromCoin: Coin,
        toCoin: Coin,
        vault: Vault,
        referredCode: String,
        slippageBps: Int?,
        recipientAddress: String?
    ) async throws -> SwapQuoteResult? { nil }

    func fetchChainSpecific(fromCoin: Coin, toCoin: Coin, fromAmount: Decimal, quote: SwapQuote?) async throws -> BlockChainSpecific {
        throw CancellationError()
    }

    func computeThorchainFee(chainSpecific: BlockChainSpecific, fromCoin: Coin, fromAmount: Decimal, vault: Vault) async throws -> BigInt {
        .zero
    }

    func assertSourceChainNotHalted(transaction: SwapTransaction) async throws {}

    func buildSwapKeysignPayload(transaction: SwapTransaction, vault: Vault) async throws -> KeysignPayload {
        throw CancellationError()
    }

    func updateBalance(for coin: Coin) async {}

    func warmDiscountTier(for vault: Vault) async {}
}
// swiftlint:enable async_without_await unused_parameter
