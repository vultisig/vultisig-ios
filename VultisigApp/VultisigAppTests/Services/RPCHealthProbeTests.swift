//
//  RPCHealthProbeTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

final class RPCHealthProbeTests: XCTestCase {

    // MARK: - EVM

    func test_evm_okWhenChainIdMatches() async {
        // Ethereum chainId 1 == 0x1
        let http = ProbeStubHTTPClient()
        http.queueDecoded(["result": "0x1"])
        let probe = RPCHealthProbe(httpClient: http)
        let result = await probe.probe(urlString: "https://eth.example/rpc", chain: .ethereum)
        guard case .ok = result else { return XCTFail("expected .ok, got \(result)") }
    }

    func test_evm_wrongChainWhenChainIdDiffers() async {
        // 0x89 == 137 (Polygon) but we probe as Ethereum (1)
        let http = ProbeStubHTTPClient()
        http.queueDecoded(["result": "0x89"])
        let probe = RPCHealthProbe(httpClient: http)
        let result = await probe.probe(urlString: "https://eth.example/rpc", chain: .ethereum)
        XCTAssertEqual(result, .wrongChain(expected: 1, got: 137))
    }

    func test_evm_invalidResponseWhenResultMissing() async {
        let http = ProbeStubHTTPClient()
        http.queueDecoded([String: String]())
        let probe = RPCHealthProbe(httpClient: http)
        let result = await probe.probe(urlString: "https://eth.example/rpc", chain: .ethereum)
        XCTAssertEqual(result, .invalidResponse)
    }

    func test_evm_unreachableOnError() async {
        let http = ProbeStubHTTPClient()
        http.queueError(HTTPError.timeout)
        let probe = RPCHealthProbe(httpClient: http)
        let result = await probe.probe(urlString: "https://eth.example/rpc", chain: .ethereum)
        XCTAssertEqual(result, .unreachable)
    }

    // MARK: - Solana

    func test_solana_okWhenHealthy() async {
        let http = ProbeStubHTTPClient()
        http.queueDecoded(["result": "ok"])
        let probe = RPCHealthProbe(httpClient: http)
        let result = await probe.probe(urlString: "https://sol.example", chain: .solana)
        guard case .ok = result else { return XCTFail("expected .ok, got \(result)") }
    }

    func test_solana_invalidWhenNotOk() async {
        let http = ProbeStubHTTPClient()
        http.queueDecoded(["result": "behind"])
        let probe = RPCHealthProbe(httpClient: http)
        let result = await probe.probe(urlString: "https://sol.example", chain: .solana)
        XCTAssertEqual(result, .invalidResponse)
    }

    // MARK: - Cosmos / THORChain (raw GET)

    func test_cosmos_okOnSuccessfulGet() async {
        let http = ProbeStubHTTPClient()
        http.queueRawSuccess()
        let probe = RPCHealthProbe(httpClient: http)
        let result = await probe.probe(urlString: "https://cosmos.example", chain: .gaiaChain)
        guard case .ok = result else { return XCTFail("expected .ok, got \(result)") }
    }

    func test_thorchain_unreachableOnError() async {
        let http = ProbeStubHTTPClient()
        http.queueError(HTTPError.statusCode(502, nil))
        let probe = RPCHealthProbe(httpClient: http)
        let result = await probe.probe(urlString: "https://thor.example", chain: .thorChain)
        XCTAssertEqual(result, .unreachable)
    }

    // MARK: - Bad URL

    func test_malformedURL_isUnreachable() async {
        let probe = RPCHealthProbe()
        let result = await probe.probe(urlString: "not a url", chain: .ethereum)
        XCTAssertEqual(result, .unreachable)
    }
}

// MARK: - Stub

private final class ProbeStubHTTPClient: HTTPClientProtocol {

    private enum Queued {
        case decoded(Any)
        case rawSuccess
        case error(Error)
    }

    private var pending: Queued?

    func queueDecoded<T>(_ value: T) { pending = .decoded(value) }
    func queueRawSuccess() { pending = .rawSuccess }
    func queueError(_ error: Error) { pending = .error(error) }

    private func stubResponse() -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://test.local")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    // swiftlint:disable async_without_await
    func request(_: TargetType) async throws -> HTTPResponse<Data> {
        switch pending {
        case .rawSuccess:
            pending = nil
            return HTTPResponse(data: Data(), response: stubResponse())
        case .error(let error):
            pending = nil
            throw error
        default:
            throw HTTPError.invalidResponse
        }
    }

    func request<T: Decodable>(
        _: TargetType,
        responseType _: T.Type
    ) async throws -> HTTPResponse<T> {
        guard let pending else { throw HTTPError.invalidResponse }
        self.pending = nil
        switch pending {
        case .error(let error):
            throw error
        case .decoded(let raw):
            // The probe decodes into small structs; re-encode the queued
            // dictionary through JSON so the stub matches real decoding.
            let data = try JSONSerialization.data(withJSONObject: raw)
            do {
                let decoded = try JSONDecoder().decode(T.self, from: data)
                return HTTPResponse(data: decoded, response: stubResponse())
            } catch {
                throw HTTPError.decodingFailed(error)
            }
        case .rawSuccess:
            throw HTTPError.invalidResponse
        }
    }

    func requestEmpty(_: TargetType) async throws -> HTTPResponse<EmptyResponse> {
        throw HTTPError.invalidResponse
    }
    // swiftlint:enable async_without_await
}
