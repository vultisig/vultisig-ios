//
//  SuiServiceRPCTransportTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

/// Sui's gas-price, broadcast and dry-run calls used to bypass `HTTPClient`
/// through a raw `URLSession` helper that discarded the `URLResponse` entirely.
/// These pin the behaviour of the typed replacements, and — for the two calls on
/// the fund path — that the already-signed base64 strings reach the wire byte
/// for byte.
final class SuiServiceRPCTransportTests: XCTestCase {

    /// A real base64 BCS `TransactionData` payload shape: it must survive the
    /// transport untouched, padding and all.
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

    // MARK: - Reference gas price

    func testReferenceGasPriceDecodesTheResult() async throws {
        http.queueDecoded(SuiReferenceGasPriceResponse(result: "750", error: nil))

        let price = try await makeService().getReferenceGasPrice()

        XCTAssertEqual(price.description, "750")
        XCTAssertEqual(Self.method(of: http.recordedTargets[0]), "suix_getReferenceGasPrice")
    }

    func testReferenceGasPriceThrowsInsteadOfReturningZeroOnAMissingResult() async {
        // Returning zero here silently under-prices the transaction built from
        // it, which then fails on chain instead of failing at the fetch.
        http.queueDecoded(SuiReferenceGasPriceResponse(result: nil, error: nil))

        await assertThrows(
            { _ = try await self.makeService().getReferenceGasPrice() },
            description: "Sui did not return a reference gas price"
        )
    }

    func testReferenceGasPriceThrowsOnAnUnparseableResult() async {
        // `String.toBigInt()` answers zero for anything it cannot parse, which
        // would reinstate the silent-zero bug behind a non-empty string.
        http.queueDecoded(SuiReferenceGasPriceResponse(result: "not-a-number", error: nil))

        await assertThrows(
            { _ = try await self.makeService().getReferenceGasPrice() },
            description: "Sui did not return a reference gas price"
        )
    }

    func testReferenceGasPriceSurfacesTheNodeRefusal() async {
        http.queueDecoded(SuiReferenceGasPriceResponse(
            result: nil,
            error: SuiRPCError(code: -32000, message: "node unavailable")
        ))

        await assertThrows(
            { _ = try await self.makeService().getReferenceGasPrice() },
            description: "Sui reference gas price RPC failed: node unavailable"
        )
    }

    // MARK: - Broadcast

    func testBroadcastSendsTheSignedBytesVerbatim() async throws {
        http.queueDecoded(SuiExecuteTransactionResponse(
            result: SuiExecuteTransactionResponse.Result(digest: "0xdigest"),
            error: nil
        ))

        let digest = try await makeService().executeTransactionBlock(
            unsignedTransaction: Self.txBytes,
            signature: Self.signature
        )

        XCTAssertEqual(digest, "0xdigest")

        let body = Self.body(of: http.recordedTargets[0])
        XCTAssertEqual(body["method"] as? String, "sui_executeTransactionBlock")
        let params = body["params"] as? [Any]
        XCTAssertEqual(params?.count, 2)
        XCTAssertEqual(params?[0] as? String, Self.txBytes)
        XCTAssertEqual(params?[1] as? [String], [Self.signature])
    }

    func testBroadcastFailureThrowsRatherThanReturningTheMessageAsADigest() async {
        http.queueDecoded(SuiExecuteTransactionResponse(
            result: nil,
            error: SuiRPCError(code: -32002, message: "invalid signature")
        ))

        await assertThrows(
            {
                _ = try await self.makeService().executeTransactionBlock(
                    unsignedTransaction: Self.txBytes,
                    signature: Self.signature
                )
            },
            description: "Sui broadcast failed: invalid signature"
        )
    }

    func testBroadcastWithoutADigestThrows() async {
        http.queueDecoded(SuiExecuteTransactionResponse(
            result: SuiExecuteTransactionResponse.Result(digest: ""),
            error: nil
        ))

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

    // MARK: - Dry run

    func testDryRunSendsTheSameBytesAndReturnsTheGasSplit() async throws {
        http.queueDecoded(Self.dryRun(computationCost: "100000", storageCost: "988000"))

        let (computation, storage) = try await makeService()
            .dryRunTransaction(transactionBytes: Self.txBytes)

        XCTAssertEqual(computation.description, "100000")
        XCTAssertEqual(storage.description, "988000")

        let body = Self.body(of: http.recordedTargets[0])
        XCTAssertEqual(body["method"] as? String, "sui_dryRunTransactionBlock")
        XCTAssertEqual((body["params"] as? [Any])?.first as? String, Self.txBytes)
    }

    func testDryRunSurfacesAnExecutionAbort() async {
        http.queueDecoded(Self.dryRun(statusError: "MoveAbort(...)"))

        await assertThrows(
            { _ = try await self.makeService().dryRunTransaction(transactionBytes: Self.txBytes) },
            description: "Simulation Error: MoveAbort(...)"
        )
    }

    func testDryRunSurfacesANodeRefusalInsteadOfAParseFailure() async {
        // Previously a JSON-RPC error fell through to "failed to parse gas
        // estimate", which hid the real reason from the user.
        http.queueDecoded(SuiDryRunResponse(
            result: nil,
            error: SuiRPCError(code: -32602, message: "cannot decode transaction")
        ))

        await assertThrows(
            { _ = try await self.makeService().dryRunTransaction(transactionBytes: Self.txBytes) },
            description: "Simulation Error: cannot decode transaction"
        )
    }

    func testDryRunWithoutGasCostsThrows() async {
        http.queueDecoded(SuiDryRunResponse(result: nil, error: nil))

        await assertThrows(
            { _ = try await self.makeService().dryRunTransaction(transactionBytes: Self.txBytes) },
            description: "Failed to parse gas estimate from dry run"
        )
    }

    // MARK: - Decoding real node payloads

    // The models above are hand-written replacements for dot-path probing of raw
    // JSON, so they are pinned against payloads shaped like the node's.

    func testReferenceGasPriceDecodesARealPayload() throws {
        let response = try Self.decode(
            SuiReferenceGasPriceResponse.self,
            from: #"{"jsonrpc":"2.0","id":1,"result":"100"}"#
        )

        XCTAssertEqual(response.result, "100")
        XCTAssertNil(response.error)
    }

    func testBroadcastDecodesARealPayloadAndIgnoresTheUnmodelledEffects() throws {
        let response = try Self.decode(
            SuiExecuteTransactionResponse.self,
            from: """
            {"jsonrpc":"2.0","id":1,"result":{"digest":"9N37cT18Na72Mr6VKSw3DzofkKL8YwkceougBP31yuKx",\
            "confirmedLocalExecution":false,"effects":{"messageVersion":"v1","status":{"status":"success"}}}}
            """
        )

        XCTAssertEqual(response.result?.digest, "9N37cT18Na72Mr6VKSw3DzofkKL8YwkceougBP31yuKx")
        XCTAssertNil(response.error)
    }

    func testBroadcastDecodesAnErrorPayload() throws {
        let response = try Self.decode(
            SuiExecuteTransactionResponse.self,
            from: #"{"jsonrpc":"2.0","id":1,"error":{"code":-32002,"message":"Invalid user signature"}}"#
        )

        XCTAssertNil(response.result)
        XCTAssertEqual(response.error, SuiRPCError(code: -32002, message: "Invalid user signature"))
    }

    func testDryRunDecodesARealPayload() throws {
        let response = try Self.decode(
            SuiDryRunResponse.self,
            from: """
            {"jsonrpc":"2.0","id":1,"result":{"effects":{"messageVersion":"v1",\
            "status":{"status":"success"},"executedEpoch":"1215",\
            "gasUsed":{"computationCost":"100000","storageCost":"988000",\
            "storageRebate":"978120","nonRefundableStorageFee":"9880"}}}}
            """
        )

        XCTAssertEqual(response.result?.effects?.gasUsed?.computationCost, "100000")
        XCTAssertEqual(response.result?.effects?.gasUsed?.storageCost, "988000")
        XCTAssertEqual(response.result?.effects?.status?.status, "success")
        XCTAssertNil(response.result?.effects?.status?.error)
    }

    func testDryRunDecodesAnAbortedExecution() throws {
        let response = try Self.decode(
            SuiDryRunResponse.self,
            from: """
            {"jsonrpc":"2.0","id":1,"result":{"effects":{"status":\
            {"status":"failure","error":"MoveAbort(...) in command 0"}}}}
            """
        )

        XCTAssertEqual(response.result?.effects?.status?.error, "MoveAbort(...) in command 0")
        XCTAssertNil(response.result?.effects?.gasUsed)
    }

    // MARK: - Helpers

    private static func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

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

    private static func dryRun(
        computationCost: String? = nil,
        storageCost: String? = nil,
        statusError: String? = nil
    ) -> SuiDryRunResponse {
        SuiDryRunResponse(
            result: SuiDryRunResponse.Result(
                effects: SuiDryRunResponse.Effects(
                    status: SuiDryRunResponse.Status(status: "success", error: statusError),
                    gasUsed: SuiDryRunResponse.GasUsed(
                        computationCost: computationCost,
                        storageCost: storageCost
                    )
                )
            ),
            error: nil
        )
    }

    private static func body(of target: TargetType) -> [String: Any] {
        guard case .requestParameters(let params, .jsonEncoding) = target.task else {
            XCTFail("Expected JSON-encoded parameters")
            return [:]
        }
        return params
    }

    private static func method(of target: TargetType) -> String? {
        body(of: target)["method"] as? String
    }
}

private struct NoOverrideSuiResolver: RPCEndpointResolving {
    func url(for _: Chain) -> String? { nil }
}

/// Captures every `TargetType` it is handed so a test can assert on the request
/// body, and replays a FIFO queue of decoded responses.
private final class SuiRecordingHTTPClient: HTTPClientProtocol, @unchecked Sendable {

    private enum Outcome {
        case value(Any)
        case error(Error)
    }

    private let lock = NSLock()
    private var queue: [Outcome] = []
    private var targets: [TargetType] = []

    var recordedTargets: [TargetType] {
        lock.lock()
        defer { lock.unlock() }
        return targets
    }

    func queueDecoded<T>(_ value: T) {
        lock.lock()
        defer { lock.unlock() }
        queue.append(.value(value))
    }

    func queueError(_ error: Error) {
        lock.lock()
        defer { lock.unlock() }
        queue.append(.error(error))
    }

    // Protocol requires `async`; the body is sync. SwiftLint can't see across
    // protocol conformance, so silence the false-positive lint here.
    // swiftlint:disable async_without_await
    func request(_: TargetType) async throws -> HTTPResponse<Data> {
        throw HTTPError.invalidResponse
    }

    func request<T: Decodable>(_ target: TargetType, responseType _: T.Type) async throws -> HTTPResponse<T> {
        lock.lock()
        targets.append(target)
        let next = queue.isEmpty ? nil : queue.removeFirst()
        lock.unlock()

        switch next {
        case .value(let value):
            guard let typed = value as? T else { throw HTTPError.invalidResponse }
            return HTTPResponse(data: typed, response: Self.okResponse(url: target.baseURL))
        case .error(let error):
            throw error
        case nil:
            throw HTTPError.noData
        }
    }
    // swiftlint:enable async_without_await

    private static func okResponse(url: URL) -> HTTPURLResponse {
        // Force-unwrap is safe: a 200 response for a valid URL always initializes.
        HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
    }
}
