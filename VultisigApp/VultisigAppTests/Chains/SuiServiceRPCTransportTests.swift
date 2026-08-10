//
//  SuiServiceRPCTransportTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

/// The fund path over GraphQL.
///
/// `executeTransaction` and `simulateTransaction` carry material that has already
/// been signed, so the assertion that matters most is not what comes back but
/// what goes out: the base64 `TransactionData` and the signature envelope must
/// reach the wire byte for byte, with the BCS bytes wrapped in the JSON-encoded
/// `sui.rpc.v2.Transaction` the simulate argument expects and nowhere re-encoded.
final class SuiServiceRPCTransportTests: XCTestCase {

    /// A base64 BCS `TransactionData` payload: it must survive the transport
    /// untouched, padding and all.
    private static let txBytes = "AAACAQEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAKzEcQySgAAAAAAQ=="
    private static let signature = "AGRlYWRiZWVmZGVhZGJlZWZkZWFkYmVlZmRlYWRiZWVmZGVhZGJlZWY="

    private var http: SuiRecordingHTTPClient!

    override func setUp() {
        super.setUp()
        http = SuiRecordingHTTPClient()
    }

    override func tearDown() {
        http = nil
        super.tearDown()
    }

    // MARK: - Broadcast: the bytes on the wire

    func testBroadcastSendsTheSignedBytesVerbatim() async throws {
        http.queue(Data("""
        {"data":{"executeTransaction":{"effects":{"digest":"0xdigest","status":"SUCCESS","executionError":null}}}}
        """.utf8))

        let digest = try await makeService().executeTransactionBlock(
            unsignedTransaction: Self.txBytes,
            signature: Self.signature
        )

        XCTAssertEqual(digest, "0xdigest")

        let body = try XCTUnwrap(http.recordedBodies.first)
        XCTAssertTrue((body["query"] as? String)?.contains("executeTransaction(transactionDataBcs:") == true)
        let variables = try XCTUnwrap(body["variables"] as? [String: Any])
        XCTAssertEqual(variables["txBytes"] as? String, Self.txBytes)
        XCTAssertEqual(variables["signatures"] as? [String], [Self.signature])
    }

    func testBroadcastRejectsAnExecutionFailureInsteadOfReturningItsDigest() async {
        // A transaction that reached the chain and aborted must not be reported
        // as a successful send, or it is persisted and polled as a real txid.
        http.queue(Data("""
        {"data":{"executeTransaction":{"effects":{"digest":"0xdigest","status":"FAILURE",\
        "executionError":{"message":"InsufficientGas","abortCode":null,"identifier":null}}}}}
        """.utf8))

        await assertThrows(
            {
                _ = try await self.makeService().executeTransactionBlock(
                    unsignedTransaction: Self.txBytes,
                    signature: Self.signature
                )
            },
            description: "Sui broadcast failed: InsufficientGas"
        )
    }

    func testBroadcastFailsClosedOnAnUnknownStatus() async {
        http.queue(Data("""
        {"data":{"executeTransaction":{"effects":{"digest":"0xdigest","status":"SOMETHING_NEW","executionError":null}}}}
        """.utf8))

        await assertThrows(
            {
                _ = try await self.makeService().executeTransactionBlock(
                    unsignedTransaction: Self.txBytes,
                    signature: Self.signature
                )
            },
            description: "Sui broadcast failed: SOMETHING_NEW"
        )
    }

    func testBroadcastWithoutADigestThrows() async {
        http.queue(Data("""
        {"data":{"executeTransaction":{"effects":{"digest":null,"status":"SUCCESS","executionError":null}}}}
        """.utf8))

        await assertThrows(
            {
                _ = try await self.makeService().executeTransactionBlock(
                    unsignedTransaction: Self.txBytes,
                    signature: Self.signature
                )
            },
            description: "Sui broadcast did not return a transaction digest"
        )
    }

    func testBroadcastSurfacesANodeRefusal() async {
        http.queue(Data(
            #"{"data":null,"errors":[{"message":"Invalid signature format","extensions":{"code":"BAD_USER_INPUT"}}]}"#.utf8
        ))

        await assertThrows(
            {
                _ = try await self.makeService().executeTransactionBlock(
                    unsignedTransaction: Self.txBytes,
                    signature: Self.signature
                )
            },
            description: "Sui RPC error (BAD_USER_INPUT): Invalid signature format"
        )
    }

    // MARK: - Dry run: the same bytes, wrapped

    func testDryRunWrapsTheSameBytesAndReturnsTheGasSplit() async throws {
        http.queue(Self.simulation(computation: 100_000, storage: 988_000))

        let (computation, storage) = try await makeService()
            .dryRunTransaction(transactionBytes: Self.txBytes)

        XCTAssertEqual(computation.description, "100000")
        XCTAssertEqual(storage.description, "988000")

        let body = try XCTUnwrap(http.recordedBodies.first)
        XCTAssertTrue((body["query"] as? String)?.contains("simulateTransaction(transaction:") == true)
        let variables = try XCTUnwrap(body["variables"] as? [String: Any])
        let transaction = try XCTUnwrap(variables["tx"] as? [String: Any])
        let bcs = try XCTUnwrap(transaction["bcs"] as? [String: Any])
        XCTAssertEqual(
            bcs["value"] as? String,
            Self.txBytes,
            "The BCS bytes must ride inside the JSON transaction unchanged"
        )
    }

    func testDryRunAndBroadcastSendIdenticalBytesForTheSameTransaction() async throws {
        // The simulated transaction and the broadcast one must be the same
        // bytes, or the fee was estimated for something else.
        http.queue(Self.simulation(computation: 1, storage: 1))
        http.queue(Data("""
        {"data":{"executeTransaction":{"effects":{"digest":"0xdigest","status":"SUCCESS","executionError":null}}}}
        """.utf8))

        let service = makeService()
        _ = try await service.dryRunTransaction(transactionBytes: Self.txBytes)
        _ = try await service.executeTransactionBlock(
            unsignedTransaction: Self.txBytes,
            signature: Self.signature
        )

        let bodies = http.recordedBodies
        XCTAssertEqual(bodies.count, 2)
        let simulated = ((bodies[0]["variables"] as? [String: Any])?["tx"] as? [String: Any])
            .flatMap { $0["bcs"] as? [String: Any] }?["value"] as? String
        let broadcast = (bodies[1]["variables"] as? [String: Any])?["txBytes"] as? String
        XCTAssertEqual(simulated, broadcast)
        XCTAssertEqual(simulated, Self.txBytes)
    }

    func testDryRunSurfacesAnExecutionAbort() async {
        http.queue(Data("""
        {"data":{"simulateTransaction":{"effects":{"digest":null,"status":"FAILURE",\
        "executionError":{"message":"MoveAbort(...)","abortCode":null,"identifier":null},\
        "gasEffects":null}}}}
        """.utf8))

        await assertThrows(
            { _ = try await self.makeService().dryRunTransaction(transactionBytes: Self.txBytes) },
            description: "Simulation Error: MoveAbort(...)"
        )
    }

    func testDryRunWithoutAGasSummaryThrows() async {
        // Falling back to zero would collapse the budget to the protocol
        // minimum instead of letting the caller apply its default budget.
        http.queue(Data("""
        {"data":{"simulateTransaction":{"effects":{"digest":null,"status":"SUCCESS",\
        "executionError":null,"gasEffects":null}}}}
        """.utf8))

        await assertThrows(
            { _ = try await self.makeService().dryRunTransaction(transactionBytes: Self.txBytes) },
            description: "Failed to parse gas estimate from dry run"
        )
    }

    // MARK: - Reference gas price

    func testReferenceGasPriceDecodesTheResult() async throws {
        http.queue(Data(#"{"data":{"epoch":{"referenceGasPrice":"750"}}}"#.utf8))

        let price = try await makeService().getReferenceGasPrice()

        XCTAssertEqual(price.description, "750")
    }

    func testReferenceGasPriceThrowsOnAnUnparseableResult() async {
        http.queue(Data(#"{"data":{"epoch":{"referenceGasPrice":"not-a-number"}}}"#.utf8))

        await assertThrows(
            { _ = try await self.makeService().getReferenceGasPrice() },
            description: "Sui did not return a reference gas price"
        )
    }

    func testReferenceGasPriceRejectsZero() async {
        // Sui's reference gas price is a positive protocol parameter, and a zero
        // silently under-prices every transaction built from it.
        http.queue(Data(#"{"data":{"epoch":{"referenceGasPrice":"0"}}}"#.utf8))

        await assertThrows(
            { _ = try await self.makeService().getReferenceGasPrice() },
            description: "Sui did not return a reference gas price"
        )
    }

    func testReferenceGasPriceThrowsWhenTheEpochIsAbsent() async {
        http.queue(Data(#"{"data":{"epoch":null}}"#.utf8))

        await assertThrows(
            { _ = try await self.makeService().getReferenceGasPrice() },
            description: "Sui did not return a reference gas price"
        )
    }

    // MARK: - Helpers

    private func makeService() -> SuiService {
        SuiService(resolver: NoOverrideSuiResolver(), httpClient: http)
    }

    private func assertThrows(
        _ operation: () async throws -> Void,
        description: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("Expected an error", file: file, line: line)
        } catch {
            XCTAssertEqual(error.localizedDescription, description, file: file, line: line)
        }
    }

    private static func simulation(computation: Int, storage: Int) -> Data {
        Data("""
        {"data":{"simulateTransaction":{"effects":{"digest":"0xsim","status":"SUCCESS",\
        "executionError":null,"gasEffects":{"gasSummary":{"computationCost":\(computation),\
        "storageCost":\(storage),"storageRebate":0,"nonRefundableStorageFee":0}}}}}}
        """.utf8)
    }
}

private struct NoOverrideSuiResolver: RPCEndpointResolving {
    func url(for _: Chain) -> String? { nil }
}

/// Replays raw payloads through the real `JSONDecoder` and records every request
/// body, so both the GraphQL envelope decoding and the exact bytes sent are
/// exercised rather than assumed.
private final class SuiRecordingHTTPClient: HTTPClientProtocol, @unchecked Sendable {

    private let lock = NSLock()
    private var payloads: [Data] = []
    private var bodies: [[String: Any]] = []

    var recordedBodies: [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return bodies
    }

    func queue(_ payload: Data) {
        lock.lock()
        defer { lock.unlock() }
        payloads.append(payload)
    }

    // Protocol requires `async`; the body is sync. SwiftLint can't see across
    // protocol conformance, so silence the false-positive lint here.
    // swiftlint:disable async_without_await
    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        lock.lock()
        if case .requestParameters(let body, _) = target.task {
            bodies.append(body)
        }
        let next = payloads.isEmpty ? nil : payloads.removeFirst()
        lock.unlock()

        guard let next else { throw HTTPError.noData }
        // Force-unwrap is safe: a 200 response for a valid URL always initializes.
        let response = HTTPURLResponse(url: target.baseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return HTTPResponse(data: next, response: response)
    }
    // swiftlint:enable async_without_await
}
