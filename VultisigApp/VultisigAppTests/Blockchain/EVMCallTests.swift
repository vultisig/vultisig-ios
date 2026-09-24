//
//  EVMCallTests.swift
//  VultisigAppTests
//
//  `eth_call` answers read raw: a node-reported revert has to stay
//  distinguishable from a node that failed to run the call. The shared
//  `sendRPCRequest` folds `error.data` over `error.message`, so a revert with
//  data reaches its callers as bare hex.
//

import XCTest
@testable import VultisigApp

final class EVMCallTests: XCTestCase {

    override func setUp() {
        super.setUp()
        EVMCallRPCStub.reset()
        URLProtocol.registerClass(EVMCallRPCStub.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(EVMCallRPCStub.self)
        EVMCallRPCStub.reset()
        super.tearDown()
    }

    // MARK: - Revert classifier

    func testExecutionErrorCodeIsARevert() {
        XCTAssertTrue(EVMRevertClassifier.isExecutionRevert(code: 3, message: "execution reverted: Ownable: caller is not the owner"))
        XCTAssertTrue(EVMRevertClassifier.isExecutionRevert(code: 3, message: nil))
    }

    /// USDT's bare `revert()`: no data, so the node reports the generic -32000.
    func testGenericExecutionRevertedWithoutDataIsARevert() {
        XCTAssertTrue(EVMRevertClassifier.isExecutionRevert(code: -32000, message: "execution reverted"))
        XCTAssertTrue(EVMRevertClassifier.isExecutionRevert(code: -32000, message: "  Execution Reverted\n"))
    }

    func testGenericExecutionRevertedWithReasonIsARevert() {
        XCTAssertTrue(EVMRevertClassifier.isExecutionRevert(code: -32000, message: "execution reverted: SafeERC20: approve from non-zero"))
        XCTAssertTrue(EVMRevertClassifier.isExecutionRevert(code: -32603, message: "VM Exception while processing transaction: revert"))
    }

    func testOtherNodeErrorsAreNotReverts() {
        XCTAssertFalse(EVMRevertClassifier.isExecutionRevert(code: -32000, message: "insufficient funds for gas * price + value"))
        XCTAssertFalse(EVMRevertClassifier.isExecutionRevert(code: -32000, message: "header not found"))
        XCTAssertFalse(EVMRevertClassifier.isExecutionRevert(code: -32000, message: "out of gas"))
        XCTAssertFalse(EVMRevertClassifier.isExecutionRevert(code: -32005, message: "rate limit exceeded"))
        XCTAssertFalse(EVMRevertClassifier.isExecutionRevert(code: -32000, message: nil))
        XCTAssertFalse(EVMRevertClassifier.isExecutionRevert(code: nil, message: nil))
    }

    // MARK: - Outcome

    func testOutcomeKeepsTheMessageWhenTheErrorCarriesData() throws {
        let outcome = try EVMCallOutcome(jsonRPCResponse: [
            "error": ["code": 3, "message": "execution reverted: nope", "data": Self.revertData]
        ])

        XCTAssertEqual(outcome, .failed(code: 3, message: "execution reverted: nope"))
    }

    func testOutcomeReadsResultData() throws {
        XCTAssertEqual(try EVMCallOutcome(jsonRPCResponse: ["result": "0x"]), .returned(data: "0x"))
    }

    func testOutcomeWithNeitherResultNorErrorThrows() {
        XCTAssertThrowsError(try EVMCallOutcome(jsonRPCResponse: ["jsonrpc": "2.0", "id": 1]))
        XCTAssertThrowsError(try EVMCallOutcome(jsonRPCResponse: ["result": 5]))
    }

    // MARK: - Over the wire

    func testEthCallSendsFromToAndDataAgainstLatest() async throws {
        EVMCallRPCStub.configure(body: #"{"jsonrpc":"2.0","id":1,"result":"0x"}"#)

        let outcome = try await service().ethCall(from: "0xowner", to: "0xtoken", data: "0x095ea7b3")

        XCTAssertEqual(outcome, .returned(data: "0x"))
        let request = try XCTUnwrap(EVMCallRPCStub.lastRequest)
        XCTAssertEqual(request["method"] as? String, "eth_call")
        let params = try XCTUnwrap(request["params"] as? [Any])
        XCTAssertEqual(params.first as? [String: String], ["from": "0xowner", "to": "0xtoken", "data": "0x095ea7b3"])
        XCTAssertEqual(params.last as? String, "latest")
    }

    func testEthCallWithoutFromOmitsIt() async throws {
        EVMCallRPCStub.configure(body: #"{"jsonrpc":"2.0","id":1,"result":"0x"}"#)

        _ = try await service().ethCall(from: nil, to: "0xtoken", data: "0xdd62ed3e")

        let params = try XCTUnwrap(EVMCallRPCStub.lastRequest?["params"] as? [Any])
        XCTAssertEqual(params.first as? [String: String], ["to": "0xtoken", "data": "0xdd62ed3e"])
    }

    func testEthCallReportsARevertWithDataByItsCodeAndMessage() async throws {
        EVMCallRPCStub.configure(body: #"{"jsonrpc":"2.0","id":1,"error":{"code":3,"message":"execution reverted: nope","data":"\#(Self.revertData)"}}"#)

        let outcome = try await service().ethCall(from: nil, to: "0xtoken", data: "0x")

        XCTAssertEqual(outcome, .failed(code: 3, message: "execution reverted: nope"))
    }

    func testEthCallReportsABareRevert() async throws {
        EVMCallRPCStub.configure(body: #"{"jsonrpc":"2.0","id":1,"error":{"code":-32000,"message":"execution reverted"}}"#)

        let outcome = try await service().ethCall(from: nil, to: "0xtoken", data: "0x")

        XCTAssertEqual(outcome, .failed(code: -32000, message: "execution reverted"))
    }

    func testEthCallTransportErrorThrows() async {
        EVMCallRPCStub.configure(error: URLError(.timedOut))

        do {
            _ = try await service().ethCall(from: nil, to: "0xtoken", data: "0x")
            XCTFail("Expected the transport error")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .timedOut)
        } catch {
            XCTFail("Expected URLError, got \(error)")
        }
    }

    /// The existing path is unchanged: the same revert still surfaces as its data.
    func testSendRPCRequestStillReportsErrorDataOverMessage() async throws {
        EVMCallRPCStub.configure(body: #"{"jsonrpc":"2.0","id":1,"error":{"code":3,"message":"execution reverted: nope","data":"\#(Self.revertData)"}}"#)
        let rpc = try RpcServiceStruct(Self.endpoint)

        do {
            _ = try await rpc.strRpcCall(method: "eth_call", params: [["to": "0xtoken", "data": "0x"], "latest"])
            XCTFail("Expected an RPC error")
        } catch let RpcServiceError.rpcError(code, message) {
            XCTAssertEqual(code, 3)
            XCTAssertEqual(message, Self.revertData)
        }
    }

    // MARK: - Helpers

    private static let endpoint = "https://evm-call-stub.local/rpc"
    private static let revertData = "0x08c379a0"
        + "0000000000000000000000000000000000000000000000000000000000000020"
        + "0000000000000000000000000000000000000000000000000000000000000004"
        + "6e6f706500000000000000000000000000000000000000000000000000000000"

    private func service() throws -> EvmServiceStruct {
        try EvmServiceStruct(config: EvmServiceConfig(chain: .ethereum, rpcEndpoint: Self.endpoint, tokenProvider: .standard))
    }
}

private final class EVMCallRPCStub: URLProtocol {
    private enum Outcome {
        case response(Data)
        case error(Error)
    }

    private static let lock = NSLock()
    private static var outcome = Outcome.response(Data("{}".utf8))
    private static var request: [String: Any]?

    static var lastRequest: [String: Any]? {
        lock.lock()
        defer { lock.unlock() }
        return request
    }

    static func configure(body: String) {
        lock.lock()
        defer { lock.unlock() }
        outcome = .response(Data(body.utf8))
    }

    static func configure(error: Error) {
        lock.lock()
        defer { lock.unlock() }
        outcome = .error(error)
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        outcome = .response(Data("{}".utf8))
        request = nil
    }

    private static func record(_ urlRequest: URLRequest) {
        // `URLProtocol` strips the body from the request; it survives on the stream.
        guard let body = urlRequest.httpBody ?? urlRequest.httpBodyStream.map(Self.readAll) else { return }
        let parsed = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        lock.lock()
        request = parsed
        lock.unlock()
    }

    private static func readAll(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        let size = 4096
        var buffer = [UInt8](repeating: 0, count: size)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: size)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }

    // These are required `URLProtocol` class-method overrides; they cannot be `static`.
    // swiftlint:disable static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool {
        guard request.url?.host == "evm-call-stub.local" else { return false }
        record(request)
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    // swiftlint:enable static_over_final_class

    override func startLoading() {
        let current: Outcome
        Self.lock.lock()
        current = Self.outcome
        Self.lock.unlock()

        switch current {
        case .response(let data):
            // Force-unwraps are safe: the URL came from the intercepted request
            // and a 200 response always initializes.
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .error(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
