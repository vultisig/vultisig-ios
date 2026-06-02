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
        guard case .ok(_, let verified) = result else { return XCTFail("expected .ok, got \(result)") }
        XCTAssertTrue(verified, "EVM chainId match should be network-verified")
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

    // MARK: - THORChain / Maya verified

    func test_thorchain_okIsNetworkVerified() async {
        let http = ProbeStubHTTPClient()
        http.queueRawSuccess()
        let probe = RPCHealthProbe(httpClient: http)
        let result = await probe.probe(urlString: "https://thor.example", chain: .thorChain)
        guard case .ok(_, let verified) = result else { return XCTFail("expected .ok, got \(result)") }
        XCTAssertTrue(verified)
    }

    func test_maya_ridesThorchainLCD_isNetworkVerified() async {
        // mayaChain has chainType .THORChain, so it uses the LCD node_info probe.
        let http = ProbeStubHTTPClient()
        http.queueRawSuccess()
        let probe = RPCHealthProbe(httpClient: http)
        let result = await probe.probe(urlString: "https://maya.example", chain: .mayaChain)
        guard case .ok(_, let verified) = result else { return XCTFail("expected .ok, got \(result)") }
        XCTAssertTrue(verified)
    }

    // MARK: - Ripple (liveness-only)

    func test_ripple_okButLivenessOnly() async {
        let http = ProbeStubHTTPClient()
        http.queueDecoded(["result": ["state": ["build_version": "1.0"]]])
        let probe = RPCHealthProbe(httpClient: http)
        let result = await probe.probe(urlString: "https://xrpl.example", chain: .ripple)
        guard case .ok(_, let verified) = result else { return XCTFail("expected .ok, got \(result)") }
        XCTAssertFalse(verified, "Ripple has no chainId equivalent; should be liveness-only")
    }

    func test_ripple_invalidWhenStateMissing() async {
        let http = ProbeStubHTTPClient()
        http.queueDecoded([String: String]())
        let probe = RPCHealthProbe(httpClient: http)
        let result = await probe.probe(urlString: "https://xrpl.example", chain: .ripple)
        XCTAssertEqual(result, .invalidResponse)
    }

    // MARK: - Sui (liveness-only)

    func test_sui_okButLivenessOnly() async {
        let http = ProbeStubHTTPClient()
        http.queueDecoded(["result": "123456"])
        let probe = RPCHealthProbe(httpClient: http)
        let result = await probe.probe(urlString: "https://sui.example", chain: .sui)
        guard case .ok(_, let verified) = result else { return XCTFail("expected .ok, got \(result)") }
        XCTAssertFalse(verified)
    }

    func test_sui_invalidWhenResultMissing() async {
        let http = ProbeStubHTTPClient()
        http.queueDecoded([String: String]())
        let probe = RPCHealthProbe(httpClient: http)
        let result = await probe.probe(urlString: "https://sui.example", chain: .sui)
        XCTAssertEqual(result, .invalidResponse)
    }

    // MARK: - Substrate (Polkadot + Bittensor, liveness-only)

    func test_polkadot_okButLivenessOnly() async {
        let http = ProbeStubHTTPClient()
        http.queueDecoded(["result": ["peers": 12, "isSyncing": false]])
        let probe = RPCHealthProbe(httpClient: http)
        let result = await probe.probe(urlString: "https://dot.example", chain: .polkadot)
        guard case .ok(_, let verified) = result else { return XCTFail("expected .ok, got \(result)") }
        XCTAssertFalse(verified)
    }

    func test_bittensor_okButLivenessOnly() async {
        let http = ProbeStubHTTPClient()
        http.queueDecoded(["result": ["peers": 3, "isSyncing": false]])
        let probe = RPCHealthProbe(httpClient: http)
        let result = await probe.probe(urlString: "https://tao.example", chain: .bittensor)
        guard case .ok(_, let verified) = result else { return XCTFail("expected .ok, got \(result)") }
        XCTAssertFalse(verified)
    }

    // MARK: - Tron (liveness-only)

    func test_tron_okButLivenessOnly() async {
        let http = ProbeStubHTTPClient()
        http.queueDecoded(["blockID": "0000000000abcdef"])
        let probe = RPCHealthProbe(httpClient: http)
        let result = await probe.probe(urlString: "https://trongrid.example", chain: .tron)
        guard case .ok(_, let verified) = result else { return XCTFail("expected .ok, got \(result)") }
        XCTAssertFalse(verified)
    }

    func test_tron_invalidWhenBlockIDMissing() async {
        let http = ProbeStubHTTPClient()
        http.queueDecoded([String: String]())
        let probe = RPCHealthProbe(httpClient: http)
        let result = await probe.probe(urlString: "https://trongrid.example", chain: .tron)
        XCTAssertEqual(result, .invalidResponse)
    }

    // MARK: - Ton (liveness-only, raw GET)

    func test_ton_okButLivenessOnly() async {
        let http = ProbeStubHTTPClient()
        http.queueRawSuccess()
        let probe = RPCHealthProbe(httpClient: http)
        let result = await probe.probe(urlString: "https://toncenter.example", chain: .ton)
        guard case .ok(_, let verified) = result else { return XCTFail("expected .ok, got \(result)") }
        XCTAssertFalse(verified)
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
