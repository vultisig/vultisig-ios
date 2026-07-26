//
//  LimitOrderCancelVerifierTests.swift
//  VultisigAppTests
//
//  The question a broadcast hash cannot answer: did the chain ACCEPT the
//  cancel?
//
//  The 2026-07-21 mainnet rehearsal returned a hash, landed in a block, and was
//  refused by THORChain's handler with `could not find matching limit swap`. The
//  refusal is visible in exactly one place — the transaction's own `code` and
//  `raw_log` — and nowhere in the Midgard-backed status path every other
//  THORChain surface reads.
//

import XCTest
@testable import VultisigApp

@MainActor
final class LimitOrderCancelVerifierTests: XCTestCase {

    // MARK: - THORChain (code + raw_log)

    /// ⚠️ The rehearsal, reproduced. A non-zero code is a refusal, and its
    /// `raw_log` is the only explanation the user will ever get.
    func testARejectedThorchainDepositIsAFailureCarryingTheChainsReason() async {
        let http = StubHTTPClient(json: """
        {"tx_response":{"code":99,"height":"123",
          "raw_log":"could not find matching limit swap: internal error"}}
        """)
        let verifier = LimitOrderCancelVerifier(httpClient: http, statusChecker: UnusedStatusChecker())

        let outcome = await verifier.verifyCancelTransaction(txHash: "CANCELTX", chain: .thorChain)

        XCTAssertEqual(outcome, .failed(reason: "could not find matching limit swap: internal error"))
    }

    func testAnAcceptedThorchainDepositSucceeds() async {
        let http = StubHTTPClient(json: #"{"tx_response":{"code":0,"height":"123","raw_log":""}}"#)
        let verifier = LimitOrderCancelVerifier(httpClient: http, statusChecker: UnusedStatusChecker())

        let outcome = await verifier.verifyCancelTransaction(txHash: "CANCELTX", chain: .thorChain)

        XCTAssertEqual(outcome, .succeeded)
    }

    /// A refusal with no log still has to read as a refusal — the reason is
    /// display copy, not the verdict.
    func testARejectionWithNoLogStillFails() async {
        let http = StubHTTPClient(json: #"{"tx_response":{"code":5,"height":"1"}}"#)
        let verifier = LimitOrderCancelVerifier(httpClient: http, statusChecker: UnusedStatusChecker())

        guard case .failed = await verifier.verifyCancelTransaction(txHash: "CANCELTX", chain: .thorChain) else {
            return XCTFail("a non-zero code is a failure whatever the log says")
        }
    }

    /// ⚠️ Not indexed yet is NOT a verdict either way. Read as failure it would
    /// withdraw a good cancel record; read as success it would reinstate the bug
    /// this file exists for.
    func testAnUnindexedTransactionIsUnresolved() async {
        let http = StubHTTPClient(json: "{}")
        let verifier = LimitOrderCancelVerifier(httpClient: http, statusChecker: UnusedStatusChecker())

        let outcome = await verifier.verifyCancelTransaction(txHash: "CANCELTX", chain: .thorChain)

        XCTAssertEqual(outcome, .unresolved)
    }

    /// Rate limits, timeouts, gateway errors: transport, not consensus.
    func testATransportFailureIsUnresolved() async {
        let verifier = LimitOrderCancelVerifier(
            httpClient: FailingHTTPClient(),
            statusChecker: UnusedStatusChecker()
        )

        let outcome = await verifier.verifyCancelTransaction(txHash: "CANCELTX", chain: .thorChain)

        XCTAssertEqual(outcome, .unresolved)
    }

    func testAnEmptyHashIsUnresolvedAndAsksNothing() async {
        let http = StubHTTPClient(json: #"{"tx_response":{"code":0}}"#)
        let verifier = LimitOrderCancelVerifier(httpClient: http, statusChecker: UnusedStatusChecker())

        let outcome = await verifier.verifyCancelTransaction(txHash: "", chain: .thorChain)

        XCTAssertEqual(outcome, .unresolved)
        XCTAssertEqual(http.requestCount, 0)
    }

    // MARK: - L1 sources (shared per-chain providers)

    /// ⚠️ `.delivered`, never `.succeeded`. A confirmed dust transfer proves the
    /// memo reached somewhere Bifrost can observe it — not that THORChain found
    /// the order. THORChain dispatches an L1 `m=<` in EndBlock and its verdict
    /// reaches no REST route, so conflating the two would assert an acceptance
    /// this route cannot observe.
    func testAConfirmedL1TransferIsDeliveredNotAcceptance() async {
        let checker = StubStatusChecker(status: .confirmed)
        let verifier = LimitOrderCancelVerifier(httpClient: FailingHTTPClient(), statusChecker: checker)

        let outcome = await verifier.verifyCancelTransaction(txHash: "0xabc", chain: .ethereum)

        XCTAssertEqual(outcome, .delivered)
        XCTAssertNotEqual(outcome, .succeeded, "only THORChain's own `code == 0` is an acceptance")
        XCTAssertEqual(checker.queries.map(\.chain), [.ethereum])
    }

    func testAFailedL1TransactionCarriesItsReason() async {
        let checker = StubStatusChecker(status: .failed(reason: "reverted"))
        let verifier = LimitOrderCancelVerifier(httpClient: FailingHTTPClient(), statusChecker: checker)

        let outcome = await verifier.verifyCancelTransaction(txHash: "0xabc", chain: .ethereum)

        XCTAssertEqual(outcome, .failed(reason: "reverted"))
    }

    func testAPendingOrUnknownL1TransactionIsUnresolved() async {
        for status in [TransactionStatusResult.TransactionConfirmationStatus.pending, .notFound] {
            let verifier = LimitOrderCancelVerifier(
                httpClient: FailingHTTPClient(),
                statusChecker: StubStatusChecker(status: status)
            )

            let outcome = await verifier.verifyCancelTransaction(txHash: "0xabc", chain: .bitcoin)

            XCTAssertEqual(outcome, .unresolved, "\(status)")
        }
    }

    func testAThrowingL1LookupIsUnresolved() async {
        let verifier = LimitOrderCancelVerifier(
            httpClient: FailingHTTPClient(),
            statusChecker: ThrowingStatusChecker()
        )

        let outcome = await verifier.verifyCancelTransaction(txHash: "0xabc", chain: .bitcoin)

        XCTAssertEqual(outcome, .unresolved)
    }

    // MARK: - Endpoint wiring

    func testTheTransactionEndpointTargetsTheCosmosTxRoute() {
        let target = ThorchainMainnetAPI(.transaction(hash: "ABC123"))

        XCTAssertEqual(target.path, "/cosmos/tx/v1beta1/txs/ABC123")
        XCTAssertEqual(target.baseURL, ThorchainMainnetAPI.defaultLCDHost)
    }
}

// MARK: - Doubles

private final class StubHTTPClient: HTTPClientProtocol {
    private let json: String
    private(set) var requestCount = 0

    init(json: String) {
        self.json = json
    }

    func request(_: TargetType) async throws -> HTTPResponse<Data> { // swiftlint:disable:this async_without_await
        requestCount += 1
        let response = HTTPURLResponse(
            url: URL(staticString: "https://example.invalid"),
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return HTTPResponse(data: Data(json.utf8), response: response)
    }
}

private struct FailingHTTPClient: HTTPClientProtocol {
    struct Failure: Error {}

    func request(_: TargetType) async throws -> HTTPResponse<Data> { // swiftlint:disable:this async_without_await
        throw Failure()
    }
}

private final class StubStatusChecker: TransactionStatusChecking, @unchecked Sendable {
    private let status: TransactionStatusResult.TransactionConfirmationStatus
    private(set) var queries: [(txHash: String, chain: Chain)] = []

    init(status: TransactionStatusResult.TransactionConfirmationStatus) {
        self.status = status
    }

    func checkTransactionStatus(txHash: String, chain: Chain) async throws -> TransactionStatusResult { // swiftlint:disable:this async_without_await
        queries.append((txHash, chain))
        return TransactionStatusResult(status: status, blockNumber: nil, confirmations: nil)
    }
}

private struct ThrowingStatusChecker: TransactionStatusChecking {
    struct Failure: Error {}

    func checkTransactionStatus(txHash _: String, chain _: Chain) async throws -> TransactionStatusResult { // swiftlint:disable:this async_without_await
        throw Failure()
    }
}

/// Asserts by construction that the THORChain branch never reaches the shared
/// providers — which cannot answer this question at all, because a refused
/// `MsgDeposit` produces no Midgard action.
private struct UnusedStatusChecker: TransactionStatusChecking {
    struct Unexpected: Error {}

    func checkTransactionStatus(txHash _: String, chain _: Chain) async throws -> TransactionStatusResult { // swiftlint:disable:this async_without_await
        throw Unexpected()
    }
}
