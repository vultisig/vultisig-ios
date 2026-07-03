//
//  CosmosCw20TokenInfoTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

final class CosmosCw20TokenInfoTests: XCTestCase {

    // ASTRO on Terra — a real 32-byte CW20 contract address.
    private let astroContract = "terra1nsuqsk6kh58ulczatwev87ttq2z6r3pusulg9r24mfj2fvtzd4uq3exn26"

    // MARK: - Endpoint

    func testWasmTokenInfoEndpointPathEncodesTokenInfoQuery() {
        // The payload must be the base64 of `{"token_info":{}}` — byte-for-byte
        // the same URL the SDK's `getCw20MetaFromLCD` queries.
        let api = CosmosAPI(
            baseURL: URL(string: "https://terra-lcd.publicnode.com")!,
            endpoint: .wasmTokenInfo(contractAddress: astroContract)
        )
        XCTAssertEqual(
            api.path,
            "/cosmwasm/wasm/v1/contract/\(astroContract)/smart/eyJ0b2tlbl9pbmZvIjp7fX0="
        )
        XCTAssertEqual(api.method, .get)
    }

    func testWasmTokenBalancePathUnchangedBySharedHelper() {
        // The smart-query path builder is shared with the pre-existing balance
        // endpoint; its output must stay byte-identical (slashes in the base64
        // payload percent-encoded, `=` untouched).
        let api = CosmosAPI(
            baseURL: URL(string: "https://terra-lcd.publicnode.com")!,
            endpoint: .wasmTokenBalance(contractAddress: astroContract, base64Payload: "aGVsbG8/d29ybGQ=")
        )
        XCTAssertEqual(
            api.path,
            "/cosmwasm/wasm/v1/contract/\(astroContract)/smart/aGVsbG8%2Fd29ybGQ="
        )
    }

    // MARK: - Resolver success

    func testCw20TokenInfoDecodesTokenInfoResponse() async {
        let stub = Cw20ScriptedHTTPClient()
        stub.result = .success(name: "Eris Amplified LUNA", symbol: "ampLUNA", decimals: 6)
        let resolver = CosmosTokenMetadataResolver(httpClient: stub)

        let info = await resolver.cw20TokenInfo(chain: .terra, contractAddress: astroContract)

        XCTAssertEqual(
            info,
            CosmosCw20TokenInfo(name: "Eris Amplified LUNA", symbol: "ampLUNA", decimals: 6)
        )
    }

    func testCw20TokenInfoAcceptsZeroDecimals() async {
        let stub = Cw20ScriptedHTTPClient()
        stub.result = .success(name: "Whole Token", symbol: "WHOLE", decimals: 0)
        let resolver = CosmosTokenMetadataResolver(httpClient: stub)

        let info = await resolver.cw20TokenInfo(chain: .terra, contractAddress: astroContract)

        XCTAssertEqual(info?.decimals, 0)
    }

    func testCw20TokenInfoNameFallsBackToSymbol() async {
        let stub = Cw20ScriptedHTTPClient()
        stub.result = .json(["data": ["symbol": "NONAME", "decimals": 6]])
        let resolver = CosmosTokenMetadataResolver(httpClient: stub)

        let info = await resolver.cw20TokenInfo(chain: .terra, contractAddress: astroContract)

        XCTAssertEqual(info?.name, "NONAME")
        XCTAssertEqual(info?.symbol, "NONAME")
    }

    func testCw20TokenInfoQueriesTheSelectedChainLcd() async {
        // Chain selection must drive which LCD host is queried: the same
        // `terra1…` contract resolves against the Terra Classic LCD when the
        // user picked Terra Classic.
        let stub = Cw20ScriptedHTTPClient()
        stub.result = .success(name: "Astroport Classic", symbol: "ASTROC", decimals: 6)
        let resolver = CosmosTokenMetadataResolver(httpClient: stub)

        _ = await resolver.cw20TokenInfo(
            chain: .terraClassic,
            contractAddress: "terra1xj49zyqrwpv5k928jwfpfy2ha668nwdgkwlrg3"
        )

        XCTAssertEqual(stub.requestedBaseURLs.last?.host, "terra-classic-lcd.publicnode.com")

        _ = await resolver.cw20TokenInfo(chain: .terra, contractAddress: astroContract)
        XCTAssertEqual(stub.requestedBaseURLs.last?.host, "terra-lcd.publicnode.com")
    }

    // MARK: - Resolver failure

    func testCw20TokenInfoReturnsNilOnLcdError() async {
        // A non-CW20 contract (or a wallet address) makes the LCD answer the
        // smart query with an error status — the resolver maps that to nil so
        // the caller can surface its not-found UX.
        let stub = Cw20ScriptedHTTPClient()
        stub.result = .httpError(500)
        let resolver = CosmosTokenMetadataResolver(httpClient: stub)

        let info = await resolver.cw20TokenInfo(chain: .terra, contractAddress: astroContract)

        XCTAssertNil(info)
    }

    func testCw20TokenInfoReturnsNilForMissingSymbol() async {
        let stub = Cw20ScriptedHTTPClient()
        stub.result = .json(["data": ["name": "Some Contract State", "decimals": 6]])
        let resolver = CosmosTokenMetadataResolver(httpClient: stub)

        let info = await resolver.cw20TokenInfo(chain: .terra, contractAddress: astroContract)

        XCTAssertNil(info)
    }

    func testCw20TokenInfoReturnsNilForBlankSymbol() async {
        let stub = Cw20ScriptedHTTPClient()
        stub.result = .json(["data": ["name": "Blank", "symbol": "  ", "decimals": 6]])
        let resolver = CosmosTokenMetadataResolver(httpClient: stub)

        let info = await resolver.cw20TokenInfo(chain: .terra, contractAddress: astroContract)

        XCTAssertNil(info)
    }

    func testCw20TokenInfoReturnsNilForMissingDecimals() async {
        let stub = Cw20ScriptedHTTPClient()
        stub.result = .json(["data": ["name": "No Decimals", "symbol": "NODEC"]])
        let resolver = CosmosTokenMetadataResolver(httpClient: stub)

        let info = await resolver.cw20TokenInfo(chain: .terra, contractAddress: astroContract)

        XCTAssertNil(info)
    }

    func testCw20TokenInfoReturnsNilForNegativeDecimals() async {
        let stub = Cw20ScriptedHTTPClient()
        stub.result = .json(["data": ["name": "Bad", "symbol": "BAD", "decimals": -1]])
        let resolver = CosmosTokenMetadataResolver(httpClient: stub)

        let info = await resolver.cw20TokenInfo(chain: .terra, contractAddress: astroContract)

        XCTAssertNil(info)
    }

    func testCw20TokenInfoReturnsNilForExcessiveDecimals() async {
        // Contract-controlled decimals feed BigInt(10).power(decimals) in
        // downstream formatting; a hostile contract must not smuggle in a
        // huge exponent (same 0...36 bound as the ERC-20 metadata resolver).
        let stub = Cw20ScriptedHTTPClient()
        stub.result = .json(["data": ["name": "Hostile", "symbol": "EVIL", "decimals": 65535]])
        let resolver = CosmosTokenMetadataResolver(httpClient: stub)

        let info = await resolver.cw20TokenInfo(chain: .terra, contractAddress: astroContract)

        XCTAssertNil(info)
    }

    func testCw20TokenInfoReturnsNilForUnsupportedChain() async {
        // Chains without a Cosmos LCD config can't run a wasm smart query;
        // the resolver must bail out without touching the network.
        let stub = Cw20ScriptedHTTPClient()
        stub.result = .success(name: "X", symbol: "X", decimals: 6)
        let resolver = CosmosTokenMetadataResolver(httpClient: stub)

        let info = await resolver.cw20TokenInfo(chain: .ethereum, contractAddress: astroContract)

        XCTAssertNil(info)
        XCTAssertEqual(stub.callCount, 0)
    }

    // MARK: - Cache semantics

    func testCw20TokenInfoCachesSuccessfulLookup() async {
        let stub = Cw20ScriptedHTTPClient()
        stub.result = .success(name: "Astroport", symbol: "ASTRO", decimals: 6)
        let resolver = CosmosTokenMetadataResolver(httpClient: stub)

        let first = await resolver.cw20TokenInfo(chain: .terra, contractAddress: astroContract)
        let second = await resolver.cw20TokenInfo(chain: .terra, contractAddress: astroContract)

        XCTAssertEqual(first, second)
        XCTAssertEqual(stub.callCount, 1, "Second lookup must be served from the cache")
    }

    func testCw20TokenInfoEvictsCacheOnFailure() async {
        // A transient LCD failure must NOT poison the cache: after a failed
        // call the next call retries (and succeeds once the LCD recovers).
        let stub = Cw20ScriptedHTTPClient()
        stub.result = .httpError(503)
        let resolver = CosmosTokenMetadataResolver(httpClient: stub)

        let first = await resolver.cw20TokenInfo(chain: .terra, contractAddress: astroContract)
        XCTAssertNil(first)

        stub.result = .success(name: "Astroport", symbol: "ASTRO", decimals: 6)
        let second = await resolver.cw20TokenInfo(chain: .terra, contractAddress: astroContract)

        XCTAssertEqual(second?.symbol, "ASTRO", "Cache eviction on error must let the retry succeed")
    }
}

// MARK: - Stub HTTP client

/// Scripted HTTP client for CW20 `token_info` lookups. Responses are
/// assembled as JSON and run through the production `JSONDecoder`, so the
/// test exercises the real decode path.
private final class Cw20ScriptedHTTPClient: HTTPClientProtocol, @unchecked Sendable {

    enum ScriptedResult {
        case success(name: String, symbol: String, decimals: Int)
        case json([String: Any])
        case httpError(Int)
    }

    var result: ScriptedResult = .httpError(500)

    private let queue = DispatchQueue(label: "Cw20ScriptedHTTPClient.queue")
    private var _requestedBaseURLs: [URL] = []
    private var _callCount = 0

    var requestedBaseURLs: [URL] {
        queue.sync { _requestedBaseURLs }
    }

    var callCount: Int {
        queue.sync { _callCount }
    }

    // swiftlint:disable async_without_await
    func request(_: TargetType) async throws -> HTTPResponse<Data> {
        throw HTTPError.invalidResponse
    }

    func request<T: Decodable>(
        _ target: TargetType,
        responseType _: T.Type
    ) async throws -> HTTPResponse<T> {
        guard let api = target as? CosmosAPI else {
            throw HTTPError.invalidResponse
        }
        queue.sync {
            _callCount += 1
            _requestedBaseURLs.append(api.baseURL)
        }

        let json: [String: Any]
        switch result {
        case .success(let name, let symbol, let decimals):
            json = ["data": ["name": name, "symbol": symbol, "decimals": decimals, "total_supply": "1000000"]]
        case .json(let payload):
            json = payload
        case .httpError(let code):
            throw HTTPError.statusCode(code, nil)
        }

        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(T.self, from: data)
        let response = HTTPURLResponse(
            url: URL(string: "https://test.local")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return HTTPResponse(data: decoded, response: response)
    }

    func requestEmpty(_: TargetType) async throws -> HTTPResponse<EmptyResponse> {
        throw HTTPError.invalidResponse
    }
    // swiftlint:enable async_without_await
}
