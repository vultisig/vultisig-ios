//
//  RippleLastLedgerExpiryTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import BigInt
import SwiftData
import XCTest

final class RippleLastLedgerExpiryTests: XCTestCase {

    private static let lastLedger = 107_426_482

    // MARK: - Provider

    func testNotFoundWithoutPersistedLastLedgerStaysNotFound() async throws {
        let stub = CapturingStatusClient(Self.notFound(searchedAll: nil))
        let provider = Self.makeProvider(stub, lastLedger: nil)

        let result = try await provider.checkStatus(query: Self.query)

        XCTAssertEqual(result.status, .notFound)
        XCTAssertEqual(stub.targets.count, 1, "no anchor means no bounded second lookup")
    }

    func testNotFoundBeforeLastLedgerValidatesStaysNotFound() async throws {
        let stub = CapturingStatusClient(Self.notFound(searchedAll: nil), Self.notFound(searchedAll: false))
        let provider = Self.makeProvider(stub, lastLedger: Self.lastLedger)

        let result = try await provider.checkStatus(query: Self.query)

        XCTAssertEqual(result.status, .notFound)
    }

    func testNotFoundAfterEveryLedgerThroughLastLedgerSearchedIsExpired() async throws {
        let stub = CapturingStatusClient(Self.notFound(searchedAll: nil), Self.notFound(searchedAll: true))
        let provider = Self.makeProvider(stub, lastLedger: Self.lastLedger)

        let result = try await provider.checkStatus(query: Self.query)

        XCTAssertEqual(result.status, .failed(reason: RippleTransactionStatusProvider.expiredReason))
    }

    func testBoundedLookupSearchesThe1000LedgersEndingAtLastLedger() async throws {
        let stub = CapturingStatusClient(Self.notFound(searchedAll: nil), Self.notFound(searchedAll: true))
        _ = try await Self.makeProvider(stub, lastLedger: Self.lastLedger).checkStatus(query: Self.query)

        XCTAssertEqual(stub.ledgerRanges.last ?? nil, 107_425_483...107_426_482)
    }

    func testRangeStartNeverDropsBelowFirstLedger() async throws {
        let stub = CapturingStatusClient(Self.notFound(searchedAll: nil), Self.notFound(searchedAll: true))
        _ = try await Self.makeProvider(stub, lastLedger: 40).checkStatus(query: Self.query)

        XCTAssertEqual(stub.ledgerRanges.last ?? nil, 1...40)
    }

    func testValidatedTransactionIsConfirmedWithoutBoundedLookup() async throws {
        let stub = CapturingStatusClient(Self.validatedBody)
        let provider = Self.makeProvider(stub, lastLedger: Self.lastLedger)

        let result = try await provider.checkStatus(query: Self.query)

        XCTAssertEqual(result.status, .confirmed)
        XCTAssertEqual(stub.targets.count, 1)
    }

    func testTransactionFoundByBoundedLookupIsNotExpired() async throws {
        let stub = CapturingStatusClient(Self.notFound(searchedAll: nil), Self.validatedBody)
        let provider = Self.makeProvider(stub, lastLedger: Self.lastLedger)

        let result = try await provider.checkStatus(query: Self.query)

        XCTAssertEqual(result.status, .notFound)
    }

    func testExpiredReasonIsLocalizedForHistory() {
        let text = TransactionHistoryFailureReasonPresentation.displayText(
            for: RippleTransactionStatusProvider.expiredReason
        )

        XCTAssertEqual(text, "transactionExpiredNotIncluded".localized)
        XCTAssertNotEqual(text, RippleTransactionStatusProvider.expiredReason)
    }

    // MARK: - Anchor extraction

    func testLastLedgerSequenceComesFromChainSpecificForPlainSend() {
        let payload = Self.payload(signRipple: nil)

        XCTAssertEqual(RippleHelper.lastLedgerSequence(keysignPayload: payload), 12_345_678)
    }

    func testLastLedgerSequenceComesFromRawJsonForDappTransaction() {
        let rawJson = #"{"TransactionType":"OfferCancel","Account":"rX","LastLedgerSequence":999}"#
        let payload = Self.payload(signRipple: SignRipple(rawJson: rawJson))

        XCTAssertEqual(RippleHelper.lastLedgerSequence(keysignPayload: payload), 999)
    }

    func testDappTransactionWithoutLastLedgerSequenceHasNoAnchor() {
        let payload = Self.payload(signRipple: SignRipple(rawJson: #"{"TransactionType":"OfferCancel"}"#))

        XCTAssertNil(RippleHelper.lastLedgerSequence(keysignPayload: payload))
    }

    func testZeroLastLedgerSequenceIsNoAnchor() {
        let payload = Self.payload(signRipple: nil, lastLedgerSequence: 0)

        XCTAssertNil(RippleHelper.lastLedgerSequence(keysignPayload: payload))
    }

    // MARK: - Persistence

    @MainActor
    func testPendingRecordPersistsAndBackfillsLastLedgerSequence() throws {
        let schema = Schema([StoredPendingTransaction.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let storage = StoredPendingTransactionStorage(modelContext: container.mainContext)

        try storage.save(txHash: "legacy", chain: .ripple, status: .pending, pubKeyECDSA: "vault")
        XCTAssertNil(storage.lastLedgerSequence(txHash: "legacy"))

        try storage.save(
            txHash: "legacy", chain: .ripple, status: .pending,
            pubKeyECDSA: "vault", lastLedgerSequence: 123
        )
        XCTAssertEqual(storage.lastLedgerSequence(txHash: "legacy"), 123)

        try storage.save(
            txHash: "legacy", chain: .ripple, status: .pending,
            pubKeyECDSA: "vault", lastLedgerSequence: 456
        )
        XCTAssertEqual(storage.lastLedgerSequence(txHash: "legacy"), 123, "first anchor wins")
    }

    // MARK: - Fixtures

    private static let query = TransactionStatusQuery(txHash: "ABC123", chain: .ripple)

    private static func makeProvider(_ client: CapturingStatusClient, lastLedger: Int?) -> RippleTransactionStatusProvider {
        RippleTransactionStatusProvider(
            httpClient: client,
            sleep: { _ in },
            resolver: NoOverrides(),
            lastLedgerSequenceLookup: { _ in lastLedger }
        )
    }

    private static func notFound(searchedAll: Bool?) -> String {
        let searched = searchedAll.map { ",\"searched_all\":\($0)" } ?? ""
        return "{\"result\":{\"error\":\"txnNotFound\",\"error_code\":29,\"status\":\"error\"\(searched)}}"
    }

    private static let validatedBody = #"""
    {"result":{"validated":true,"ledger_index":123,"meta":{"TransactionResult":"tesSUCCESS"}}}
    """#

    private static func payload(signRipple: SignRipple?, lastLedgerSequence: UInt64 = 12_345_678) -> KeysignPayload {
        let meta = CoinMeta(
            chain: .ripple, ticker: "XRP", logo: "xrp", decimals: 6,
            priceProviderId: "ripple", contractAddress: "", isNativeToken: true
        )
        return KeysignPayload(
            coin: Coin(asset: meta, address: "rPVMhWBsfF9iMXYj3aAzJVkPDTFNSyWdKy", hexPublicKey: ""),
            toAddress: "rEb8TK3gBgk5auZkwc6sHnwrGVJH8DuaLh",
            toAmount: BigInt(1),
            chainSpecific: .Ripple(sequence: 1, gas: 10, lastLedgerSequence: lastLedgerSequence),
            utxos: [],
            memo: nil,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "",
            vaultLocalPartyID: "iPhone-test",
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: false,
            signData: signRipple.map { .signRipple($0) }
        )
    }
}

private struct NoOverrides: RPCEndpointResolving {
    func url(for _: Chain) -> String? { nil }
}

/// Serves queued JSON bodies in order and records each request's target.
private final class CapturingStatusClient: HTTPClientProtocol, @unchecked Sendable {
    private var bodies: [String]
    private(set) var targets: [TargetType] = []

    init(_ bodies: String...) { self.bodies = bodies }

    var ledgerRanges: [ClosedRange<Int>?] {
        targets.compactMap { target in
            guard case .getTx(_, _, let range) = target as? RippleTransactionStatusAPI else { return nil }
            return .some(range)
        }
    }

    // swiftlint:disable async_without_await
    func request(_: TargetType) async throws -> HTTPResponse<Data> { throw HTTPError.invalidResponse }

    func request<T: Decodable>(_ target: TargetType, responseType _: T.Type) async throws -> HTTPResponse<T> {
        targets.append(target)
        guard !bodies.isEmpty else { throw HTTPError.invalidResponse }
        let body = bodies.removeFirst()
        let value = try JSONDecoder().decode(T.self, from: Data(body.utf8))
        let response = HTTPURLResponse(url: target.baseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return HTTPResponse(data: value, response: response)
    }

    func requestEmpty(_: TargetType) async throws -> HTTPResponse<EmptyResponse> { throw HTTPError.invalidResponse }
    // swiftlint:enable async_without_await
}
