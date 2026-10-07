//
//  TransactionStatusPollerTimeoutTests.swift
//  VultisigAppTests
//

import SwiftData
import XCTest
@testable import VultisigApp

@MainActor
final class TransactionStatusPollerTimeoutTests: XCTestCase {
    func testExpiredTransactionChecksChainBeforeStopping() async {
        let checker = StubStatusChecker(outcome: .confirmed)

        let action = await TransactionStatusPoller.nextAction(
            checker: checker,
            txHash: "confirmed-after-deadline",
            chain: .ethereum,
            senderAccountId: "from",
            deadlineReached: true
        )
        let callCount = await checker.callCount

        XCTAssertEqual(action, .complete(.successful, nil))
        XCTAssertEqual(callCount, 1)
    }

    func testExpiredPendingTransactionStopsWithoutCreatingAnError() async {
        let checker = StubStatusChecker(outcome: .pending)

        let action = await TransactionStatusPoller.nextAction(
            checker: checker,
            txHash: "still-pending",
            chain: .ethereum,
            senderAccountId: "from",
            deadlineReached: true
        )

        XCTAssertEqual(action, .stop)
    }

    func testExpiredFailedTransactionStillRecordsTheChainFailure() async {
        let checker = StubStatusChecker(outcome: .failed("rejected by chain"))

        let action = await TransactionStatusPoller.nextAction(
            checker: checker,
            txHash: "failed-after-deadline",
            chain: .ethereum,
            senderAccountId: "from",
            deadlineReached: true
        )

        XCTAssertEqual(action, .complete(.error, "rejected by chain"))
    }

    func testExpiredStatusLookupErrorStopsWithoutCreatingAnError() async {
        let checker = StubStatusChecker(outcome: .error)

        let action = await TransactionStatusPoller.nextAction(
            checker: checker,
            txHash: "lookup-error",
            chain: .ethereum,
            senderAccountId: "from",
            deadlineReached: true
        )
        let callCount = await checker.callCount

        XCTAssertEqual(action, .stop)
        XCTAssertEqual(callCount, 1)
    }

    func testPendingTransactionRetriesBeforeDeadline() async {
        let checker = StubStatusChecker(outcome: .notFound)

        let action = await TransactionStatusPoller.nextAction(
            checker: checker,
            txHash: "not-found-yet",
            chain: .ethereum,
            senderAccountId: "from",
            deadlineReached: false
        )

        XCTAssertEqual(action, .retry)
    }

    /// NEAR cannot resolve a transaction from its hash alone — the node is asked
    /// by `(tx_hash, sender_account_id)` — so the poller has to hand the row's
    /// sender to the checker rather than dropping it on the way through.
    func testPollerPassesTheSenderAccountIdToTheChecker() async {
        let checker = StubStatusChecker(outcome: .pending)

        _ = await TransactionStatusPoller.nextAction(
            checker: checker,
            txHash: "near-hash",
            chain: .near,
            senderAccountId: "sender.near",
            deadlineReached: false
        )

        let receivedSender = await checker.lastSenderAccountId
        XCTAssertEqual(receivedSender, "sender.near")
    }

    func testLegacyTimeoutRecoveryClearsStaleTerminalFieldsAndPreservesRealErrors() throws {
        let schema = Schema([TransactionHistoryItem.self, SwapTrackingMetadata.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let storage = TransactionHistoryStorage(modelContext: context)
        let legacyTimeout = makeHistoryItem(
            txHash: "legacy-timeout",
            vault: "vault-a",
            chain: .ethereum,
            errorMessage: "Tiempo de espera agotado"
        )
        let realFailure = makeHistoryItem(
            txHash: "real-failure",
            vault: "vault-a",
            chain: .ethereum,
            errorMessage: "insufficient fee"
        )
        let otherChain = makeHistoryItem(
            txHash: "other-chain",
            vault: "vault-a",
            chain: .bitcoin,
            errorMessage: "Timeout"
        )
        let otherVault = makeHistoryItem(
            txHash: "other-vault",
            vault: "vault-b",
            chain: .ethereum,
            errorMessage: "Timeout"
        )
        [legacyTimeout, realFailure, otherChain, otherVault].forEach(context.insert)
        try context.save()

        let reopened = try storage.reopenLegacyClientTimeouts(
            pubKeyECDSA: "vault-a",
            chainRawValue: Chain.ethereum.rawValue,
            timeoutMessages: TransactionHistoryLegacyTimeout.localizedMessages()
        )

        XCTAssertEqual(reopened, 1)
        XCTAssertEqual(legacyTimeout.statusRawValue, TransactionHistoryStatus.inProgress.rawValue)
        XCTAssertNil(legacyTimeout.errorMessage)
        XCTAssertNil(legacyTimeout.completedAt)
        XCTAssertEqual(realFailure.statusRawValue, TransactionHistoryStatus.error.rawValue)
        XCTAssertEqual(realFailure.errorMessage, "insufficient fee")
        XCTAssertEqual(otherChain.statusRawValue, TransactionHistoryStatus.error.rawValue)
        XCTAssertEqual(otherVault.statusRawValue, TransactionHistoryStatus.error.rawValue)
    }

    func testLegacyTimeoutMessagesIncludeEveryReleasedLocalization() {
        let messages = TransactionHistoryLegacyTimeout.localizedMessages()

        XCTAssertTrue(messages.isSuperset(of: [
            "Timeout",
            "Isteklo vrijeme",
            "Zeitüberschreitung",
            "시간 초과",
            "Tempo scaduto",
            "超时",
            "Tempo esgotado",
            "Tiempo de espera agotado"
        ]))
    }

    func testLegacyPendingStorageTimeoutIsResumable() throws {
        let schema = Schema([StoredPendingTransaction.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let storage = StoredPendingTransactionStorage(modelContext: container.mainContext)
        try storage.save(
            txHash: "legacy-timeout",
            chain: .ethereum,
            status: .timeout,
            pubKeyECDSA: "vault-a"
        )
        try storage.save(
            txHash: "chain-failure",
            chain: .ethereum,
            status: .failed(reason: "rejected"),
            pubKeyECDSA: "vault-a"
        )

        let resumable = try storage.getAllPending()
        let transaction = try XCTUnwrap(resumable.first { $0.txHash == "legacy-timeout" })
        let viewModel = TransactionStatusViewModel(pendingTransaction: transaction, senderAccountId: nil)

        XCTAssertEqual(resumable.map(\.txHash), ["legacy-timeout"])
        XCTAssertEqual(viewModel.status, .pending)
    }

    private func makeHistoryItem(
        txHash: String,
        vault: String,
        chain: Chain,
        errorMessage: String
    ) -> TransactionHistoryItem {
        TransactionHistoryItem(
            txHash: txHash,
            pubKeyECDSA: vault,
            typeRawValue: TransactionHistoryType.send.rawValue,
            statusRawValue: TransactionHistoryStatus.error.rawValue,
            chainRawValue: chain.rawValue,
            coinTicker: "ETH",
            coinLogo: "eth",
            amountCrypto: "1",
            amountFiat: "1",
            fromAddress: "from",
            toAddress: "to",
            feeCrypto: "0.01",
            feeFiat: "0.01",
            network: chain.rawValue,
            explorerLink: "https://example.com/\(txHash)",
            completedAt: Date(),
            errorMessage: errorMessage
        )
    }
}

private actor StubStatusChecker: TransactionStatusChecking {
    enum Outcome: Sendable {
        case notFound
        case pending
        case confirmed
        case failed(String)
        case error
    }

    private(set) var callCount = 0
    private(set) var lastSenderAccountId: String?
    private let outcome: Outcome

    init(outcome: Outcome) {
        self.outcome = outcome
    }

    func checkTransactionStatus(
        txHash _: String,
        senderAccountId: String?,
        chain _: Chain
    ) async throws -> TransactionStatusResult {
        await Task.yield()
        callCount += 1
        lastSenderAccountId = senderAccountId
        switch outcome {
        case .notFound:
            return TransactionStatusResult(status: .notFound, blockNumber: nil, confirmations: nil)
        case .pending:
            return TransactionStatusResult(status: .pending, blockNumber: nil, confirmations: nil)
        case .confirmed:
            return TransactionStatusResult(status: .confirmed, blockNumber: 1, confirmations: 1)
        case let .failed(reason):
            return TransactionStatusResult(status: .failed(reason: reason), blockNumber: nil, confirmations: nil)
        case .error:
            throw StubError.lookupFailed
        }
    }
}

private enum StubError: Error {
    case lookupFailed
}
