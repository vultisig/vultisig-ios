//
//  SolanaSimulateTransactionTests.swift
//  VultisigAppTests
//
//  `simulateTransaction` is the only thing that can tell us a third-party-built
//  transaction will actually execute before a signer is asked to approve it, so
//  both halves are pinned: the request options the RPC node needs, and the
//  polymorphic `err` shape that says whether it ran.
//

@testable import VultisigApp
import XCTest

final class SolanaSimulateTransactionTests: XCTestCase {

    // MARK: - Request shape

    private func params(for method: SolanaAPI.Method) throws -> [String: Any] {
        let api = SolanaAPI(baseURL: SolanaAPI.rpcBaseURL, usesProxyPath: true, rpcMethod: method)
        guard case .requestParameters(let envelope, _) = api.task else {
            XCTFail("expected requestParameters task")
            return [:]
        }
        return envelope
    }

    func testSimulateRequestPinsBase64EncodingAndSkipsSignatureVerification() throws {
        let envelope = try params(
            for: .simulateTransaction(encodedTransaction: "dHg=", replaceRecentBlockhash: false)
        )

        XCTAssertEqual(envelope["method"] as? String, "simulateTransaction")
        let rpcParams = try XCTUnwrap(envelope["params"] as? [Any])
        XCTAssertEqual(rpcParams.first as? String, "dHg=")

        let config = try XCTUnwrap(rpcParams[1] as? [String: Any])
        XCTAssertEqual(config["encoding"] as? String, "base64")
        XCTAssertEqual(config["commitment"] as? String, "confirmed")
        // The transactions being simulated still carry an all-zero placeholder
        // signature; verifying it would fail every simulation.
        XCTAssertEqual(config["sigVerify"] as? Bool, false)
        XCTAssertEqual(config["replaceRecentBlockhash"] as? Bool, false)
    }

    func testSimulateRequestCarriesTheBlockhashReplacementFlag() throws {
        let envelope = try params(
            for: .simulateTransaction(encodedTransaction: "dHg=", replaceRecentBlockhash: true)
        )
        let rpcParams = try XCTUnwrap(envelope["params"] as? [Any])
        let config = try XCTUnwrap(rpcParams[1] as? [String: Any])

        XCTAssertEqual(config["replaceRecentBlockhash"] as? Bool, true)
        XCTAssertEqual(config["sigVerify"] as? Bool, false)
    }

    // MARK: - Response decoding

    private func makeService(_ json: String) -> SolanaService {
        SolanaService(resolver: SimulationResolver(), httpClient: SimulationStubHTTPClient(json: json))
    }

    func testCleanSimulationReportsSuccessAndComputeUsage() async throws {
        let service = makeService("""
        {"jsonrpc":"2.0","id":1,"result":{"context":{"slot":1},"value":
        {"err":null,"logs":["Program ComputeBudget111111111111111111111111111111 invoke [1]"],
        "unitsConsumed":252146,"returnData":null}}}
        """)

        let result = try await service.simulateTransaction(base64Transaction: "dHg=", replaceRecentBlockhash: false)

        XCTAssertTrue(result.succeeded)
        XCTAssertNil(result.failure)
        XCTAssertEqual(result.unitsConsumed, 252_146)
        XCTAssertEqual(result.logs.count, 1)
    }

    /// A stale blockhash comes back as a bare string, which is what the control
    /// run of the blockhash splice produced.
    func testStringErrorIsSurfacedVerbatim() async throws {
        let service = makeService("""
        {"jsonrpc":"2.0","id":1,"result":{"context":{"slot":1},"value":
        {"err":"BlockhashNotFound","logs":[],"unitsConsumed":0}}}
        """)

        let result = try await service.simulateTransaction(base64Transaction: "dHg=", replaceRecentBlockhash: false)

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.failure, "BlockhashNotFound")
        XCTAssertEqual(result.unitsConsumed, 0)
    }

    /// A program failure is an object, and the interesting part — which
    /// instruction failed, with which custom code — lives inside it. Flattening
    /// `err` to a `String?` would throw exactly that away.
    func testInstructionErrorObjectKeepsTheInstructionIndexAndCode() async throws {
        let service = makeService("""
        {"jsonrpc":"2.0","id":1,"result":{"context":{"slot":1},"value":
        {"err":{"InstructionError":[3,{"Custom":6003}]},"logs":["Program log: deposit below minimum"],
        "unitsConsumed":18000}}}
        """)

        let result = try await service.simulateTransaction(base64Transaction: "dHg=", replaceRecentBlockhash: false)

        XCTAssertFalse(result.succeeded)
        let failure = try XCTUnwrap(result.failure)
        XCTAssertTrue(failure.contains("InstructionError"), failure)
        XCTAssertTrue(failure.contains("3"), failure)
        XCTAssertTrue(failure.contains("Custom"), failure)
        XCTAssertTrue(failure.contains("6003"), failure)
        XCTAssertEqual(result.logs, ["Program log: deposit below minimum"])
    }

    /// A transport-level JSON-RPC error is not a simulation verdict — the
    /// transaction was never run, so it must not read as "would fail".
    func testTransportErrorThrowsRatherThanReportingFailure() async {
        let service = makeService("""
        {"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"Method not found"}}
        """)

        do {
            _ = try await service.simulateTransaction(base64Transaction: "dHg=", replaceRecentBlockhash: false)
            XCTFail("expected an rpcError")
        } catch let error as SolanaServiceError {
            guard case .rpcError(let message, let code) = error else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertEqual(code, -32601)
            XCTAssertEqual(message, "Method not found")
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testMissingResultThrows() async {
        let service = makeService(#"{"jsonrpc":"2.0","id":1}"#)

        do {
            _ = try await service.simulateTransaction(base64Transaction: "dHg=", replaceRecentBlockhash: false)
            XCTFail("expected an rpcError")
        } catch is SolanaServiceError {
            // expected
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }
}

private struct SimulationResolver: RPCEndpointResolving {
    // swiftlint:disable:next unused_parameter
    func url(for chain: Chain) -> String? { nil }
}

private final class SimulationStubHTTPClient: HTTPClientProtocol {

    private let json: String

    init(json: String) {
        self.json = json
    }

    // Protocol requires `async`; the body is synchronous.
    // swiftlint:disable:next async_without_await unused_parameter
    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        guard let url = URL(string: "https://test.local"),
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        else {
            throw HTTPError.invalidResponse
        }
        return HTTPResponse(data: Data(json.utf8), response: response)
    }
}
