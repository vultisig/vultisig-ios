//
//  KeysignBroadcastCancellationTests.swift
//  VultisigAppTests
//
//  Covers the cancellation-poisons-broadcast path: a co-signing device whose
//  in-flight broadcast HTTP call is cancelled (SwiftUI view teardown / scene
//  change) for a tx that may already be on-chain. The fix classifies the
//  cancellation as non-conclusive, verifies the deterministic hash in a
//  detached (non-cancelled) context, and either claims success or falls back
//  to a neutral "couldn't confirm" state — never a raw CancellationError.
//

@testable import VultisigApp
import BigInt
import os
import XCTest

@MainActor
final class KeysignBroadcastCancellationTests: XCTestCase {

    // MARK: - Fakes

    /// Records the lookups it receives and returns a scripted result (or
    /// throws). Sendable so it can cross into the detached verification task.
    private final class FakeStatusChecker: TransactionStatusChecking, @unchecked Sendable {
        enum Behavior {
            case confirmed
            case pending
            case notFound
            case fail(reason: String)
            case throwError(Error)
        }

        let behavior: Behavior
        private let callCountLock = OSAllocatedUnfairLock(initialState: 0)
        var callCount: Int {
            callCountLock.withLock { $0 }
        }

        /// Fulfilled the first time the checker is invoked. Lets a test wait
        /// until the detached verification has provably started, instead of
        /// racing it with a `task.cancel()`.
        private let firstCall: XCTestExpectation?

        init(_ behavior: Behavior, firstCall: XCTestExpectation? = nil) {
            self.behavior = behavior
            self.firstCall = firstCall
        }

        func checkTransactionStatus(txHash _: String, chain _: Chain) async throws -> TransactionStatusResult {
            await Task.yield()
            let isFirst = callCountLock.withLock { count in
                count += 1
                return count == 1
            }
            if isFirst { firstCall?.fulfill() }

            switch behavior {
            case .confirmed:
                return TransactionStatusResult(status: .confirmed, blockNumber: 1, confirmations: 1)
            case .pending:
                return TransactionStatusResult(status: .pending, blockNumber: nil, confirmations: nil)
            case .notFound:
                return TransactionStatusResult(status: .notFound, blockNumber: nil, confirmations: nil)
            case .fail(let reason):
                return TransactionStatusResult(status: .failed(reason: reason), blockNumber: nil, confirmations: nil)
            case .throwError(let error):
                throw error
            }
        }
    }

    private struct StubBroadcastError: LocalizedError {
        var errorDescription: String? { "simulated rpc failure" }
    }

    // MARK: - Fixtures

    private static let txHash = "0fdeadbeefcafef00d"

    private func makeBitcoinCoin() -> Coin {
        let asset = CoinMeta(
            chain: .bitcoin,
            ticker: "BTC",
            logo: "btc",
            decimals: 8,
            priceProviderId: "bitcoin",
            contractAddress: "",
            isNativeToken: true
        )
        return Coin(
            asset: asset,
            address: "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa",
            hexPublicKey: "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
        )
    }

    private func makePayload() -> KeysignPayload {
        KeysignPayload(
            coin: makeBitcoinCoin(),
            toAddress: "bc1q4e4y3g85dtkx0yp3l2flj2nmugf23c9wwtjwu5",
            toAmount: BigInt(10_000),
            chainSpecific: .UTXO(byteFee: 20, sendMaxAmount: false),
            utxos: [],
            memo: nil,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "ECDSAKey",
            vaultLocalPartyID: "localPartyID",
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: false,
            signData: nil
        )
    }

    private func makeViewModel(checker: TransactionStatusChecking) -> KeysignViewModel {
        let vm = KeysignViewModel()
        vm.keysignPayload = makePayload()
        vm.transactionStatusChecker = checker
        return vm
    }

    private func makeTransactionType() -> SignedTransactionType {
        .regular(SignedTransactionResult(rawTransaction: "rawhex", transactionHash: Self.txHash))
    }

    // MARK: - (A)+(B) Cancellation + on-chain → success

    func testCancellationWithHashOnChainEndsInSuccessNotFailed() async {
        let checker = FakeStatusChecker(.confirmed)
        let vm = makeViewModel(checker: checker)

        await vm.handleBroadcastError(error: CancellationError(), transactionType: makeTransactionType())

        XCTAssertEqual(vm.txid, Self.txHash)
        XCTAssertNotEqual(vm.status, .KeysignFailed)
        XCTAssertNotEqual(vm.status, .KeysignBroadcastUnconfirmed)
        XCTAssertGreaterThan(checker.callCount, 0)
    }

    func testCancellationWithHashPendingEndsInSuccess() async {
        let checker = FakeStatusChecker(.pending)
        let vm = makeViewModel(checker: checker)

        await vm.handleBroadcastError(error: CancellationError(), transactionType: makeTransactionType())

        XCTAssertEqual(vm.txid, Self.txHash)
        XCTAssertNotEqual(vm.status, .KeysignFailed)
    }

    // MARK: - (C) Cancellation + not found → neutral state, no raw error

    func testCancellationWithHashNotFoundEndsInNeutralStateWithoutCancellationText() async {
        let checker = FakeStatusChecker(.notFound)
        let vm = makeViewModel(checker: checker)

        await vm.handleBroadcastError(error: CancellationError(), transactionType: makeTransactionType())

        XCTAssertEqual(vm.status, .KeysignBroadcastUnconfirmed)
        XCTAssertNotEqual(vm.status, .KeysignFailed)
        XCTAssertEqual(vm.txid, Self.txHash, "hash should still be exposed for the explorer link")
        XCTAssertFalse(
            vm.keysignError.lowercased().contains("cancellation"),
            "user-facing string must never contain raw CancellationError text"
        )
    }

    func testURLErrorCancelledIsClassifiedAsCancellation() async {
        let checker = FakeStatusChecker(.notFound)
        let vm = makeViewModel(checker: checker)

        await vm.handleBroadcastError(
            error: URLError(.cancelled),
            transactionType: makeTransactionType()
        )

        XCTAssertEqual(vm.status, .KeysignBroadcastUnconfirmed)
        XCTAssertFalse(vm.keysignError.lowercased().contains("cancellation"))
    }

    func testHTTPErrorWrappedCancellationIsClassified() async {
        let checker = FakeStatusChecker(.notFound)
        let vm = makeViewModel(checker: checker)

        await vm.handleBroadcastError(
            error: HTTPError.networkError(CancellationError()),
            transactionType: makeTransactionType()
        )

        XCTAssertEqual(vm.status, .KeysignBroadcastUnconfirmed)
    }

    // MARK: - (B) Verification runs even under a cancelled parent context

    func testVerificationRunsDetachedEvenWhenParentTaskIsCancelled() async {
        // The fake fulfills `firstCall` the instant it is invoked, so the test
        // doesn't depend on cancel-timing luck: we cancel the parent, then wait
        // on a deterministic signal that the detached verification reached the
        // checker. A non-detached lookup would short-circuit on
        // Task.checkCancellation() and the expectation would never fulfill.
        let reachedChecker = expectation(description: "detached verification reached the checker")
        let checker = FakeStatusChecker(.confirmed, firstCall: reachedChecker)
        let vm = makeViewModel(checker: checker)
        let txType = makeTransactionType()

        let task = Task { @MainActor in
            await vm.handleBroadcastError(error: CancellationError(), transactionType: txType)
        }
        task.cancel()

        await fulfillment(of: [reachedChecker], timeout: 5)
        await task.value

        XCTAssertGreaterThan(checker.callCount, 0, "detached verification must still call the checker under a cancelled parent")
        XCTAssertEqual(vm.txid, Self.txHash)
        XCTAssertNotEqual(vm.status, .KeysignFailed)
    }

    // MARK: - Regression: genuine non-cancellation failure still fails

    func testGenuineBroadcastFailureStillEndsInKeysignFailed() async {
        // notFound so the safety-net lookup can't rescue it.
        let checker = FakeStatusChecker(.notFound)
        let vm = makeViewModel(checker: checker)

        await vm.handleBroadcastError(error: StubBroadcastError(), transactionType: makeTransactionType())

        XCTAssertEqual(vm.status, .KeysignFailed)
        XCTAssertNotEqual(vm.status, .KeysignBroadcastUnconfirmed)
    }

    func testGenuineFailureWithHashOnChainIsRescuedToSuccess() async {
        // The existing peer-race safety net: a real broadcast error whose tx is
        // already on-chain should still resolve to the success hash.
        let checker = FakeStatusChecker(.confirmed)
        let vm = makeViewModel(checker: checker)

        await vm.handleBroadcastError(error: StubBroadcastError(), transactionType: makeTransactionType())

        XCTAssertEqual(vm.txid, Self.txHash)
        XCTAssertNotEqual(vm.status, .KeysignFailed)
    }

    // MARK: - (C) Unconfirmed state is terminal and survives the finish guard

    func testBroadcastUnconfirmedIsTerminalSoFinishGuardCannotOverwriteIt() {
        // The post-broadcast guard in startKeysignDKLS/GG20 only sets
        // .KeysignFinished when the current status is not terminal. If
        // .KeysignBroadcastUnconfirmed were not terminal, the neutral
        // "couldn't confirm" state would be silently masked as a false success.
        XCTAssertTrue(KeysignViewModel.isTerminalStatus(.KeysignBroadcastUnconfirmed))
        XCTAssertTrue(KeysignViewModel.isTerminalStatus(.KeysignFailed))
        XCTAssertTrue(KeysignViewModel.isTerminalStatus(.KeysignRetryRequested))
        XCTAssertTrue(KeysignViewModel.isTerminalStatus(.KeysignVaultMismatch))
        XCTAssertTrue(KeysignViewModel.isTerminalStatus(.KeysignFinished))
        XCTAssertFalse(KeysignViewModel.isTerminalStatus(.CreatingInstance))
        XCTAssertFalse(KeysignViewModel.isTerminalStatus(.KeysignECDSA))
        XCTAssertFalse(KeysignViewModel.isTerminalStatus(.KeysignEdDSA))
        XCTAssertFalse(KeysignViewModel.isTerminalStatus(.KeysignMLDSA))
    }

    func testCancelledUnconfirmedBroadcastSurvivesPostBroadcastFinishGuard() async {
        // End-to-end of the BLOCKING fix: a cancelled broadcast whose hash is
        // NOT on-chain lands in .KeysignBroadcastUnconfirmed, and the
        // post-broadcast finish guard (simulated here) must leave it untouched
        // instead of flipping it to a false .KeysignFinished.
        let checker = FakeStatusChecker(.notFound)
        let vm = makeViewModel(checker: checker)

        await vm.handleBroadcastError(error: CancellationError(), transactionType: makeTransactionType())
        XCTAssertEqual(vm.status, .KeysignBroadcastUnconfirmed)

        // Mirror the guard at the tail of startKeysignDKLS/GG20.
        if !KeysignViewModel.isTerminalStatus(vm.status) {
            vm.status = .KeysignFinished
        }

        XCTAssertEqual(vm.status, .KeysignBroadcastUnconfirmed, "finish guard must not overwrite the unconfirmed state")
    }

    // MARK: - Classifier unit coverage

    func testIsCancellationClassifier() {
        XCTAssertTrue(KeysignViewModel.isCancellation(CancellationError()))
        XCTAssertTrue(KeysignViewModel.isCancellation(URLError(.cancelled)))
        XCTAssertTrue(KeysignViewModel.isCancellation(HTTPError.networkError(CancellationError())))
        XCTAssertFalse(KeysignViewModel.isCancellation(URLError(.timedOut)))
        XCTAssertFalse(KeysignViewModel.isCancellation(StubBroadcastError()))
        XCTAssertFalse(KeysignViewModel.isCancellation(HTTPError.timeout))
    }
}
