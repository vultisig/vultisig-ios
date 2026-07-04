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

    func testCw20TokenInfoDecodesTokenInfoResponse() async throws {
        let stub = Cw20ScriptedHTTPClient()
        stub.result = .success(name: "Eris Amplified LUNA", symbol: "ampLUNA", decimals: 6)
        let resolver = CosmosTokenMetadataResolver(httpClient: stub)

        let info = try await resolver.cw20TokenInfo(chain: .terra, contractAddress: astroContract)

        XCTAssertEqual(
            info,
            CosmosCw20TokenInfo(name: "Eris Amplified LUNA", symbol: "ampLUNA", decimals: 6)
        )
    }

    func testCw20TokenInfoAcceptsZeroDecimals() async throws {
        let stub = Cw20ScriptedHTTPClient()
        stub.result = .success(name: "Whole Token", symbol: "WHOLE", decimals: 0)
        let resolver = CosmosTokenMetadataResolver(httpClient: stub)

        let info = try await resolver.cw20TokenInfo(chain: .terra, contractAddress: astroContract)

        XCTAssertEqual(info?.decimals, 0)
    }

    func testCw20TokenInfoNameFallsBackToSymbol() async throws {
        let stub = Cw20ScriptedHTTPClient()
        stub.result = .json(["data": ["symbol": "NONAME", "decimals": 6]])
        let resolver = CosmosTokenMetadataResolver(httpClient: stub)

        let info = try await resolver.cw20TokenInfo(chain: .terra, contractAddress: astroContract)

        XCTAssertEqual(info?.name, "NONAME")
        XCTAssertEqual(info?.symbol, "NONAME")
    }

    func testCw20TokenInfoQueriesTheSelectedChainLcd() async throws {
        // Chain selection must drive which LCD host is queried: the same
        // `terra1…` contract resolves against the Terra Classic LCD when the
        // user picked Terra Classic.
        let stub = Cw20ScriptedHTTPClient()
        stub.result = .success(name: "Astroport Classic", symbol: "ASTROC", decimals: 6)
        let resolver = CosmosTokenMetadataResolver(httpClient: stub)

        _ = try await resolver.cw20TokenInfo(
            chain: .terraClassic,
            contractAddress: "terra1xj49zyqrwpv5k928jwfpfy2ha668nwdgkwlrg3"
        )

        XCTAssertEqual(stub.requestedBaseURLs.last?.host, "terra-classic-lcd.publicnode.com")

        _ = try await resolver.cw20TokenInfo(chain: .terra, contractAddress: astroContract)
        XCTAssertEqual(stub.requestedBaseURLs.last?.host, "terra-lcd.publicnode.com")
    }

    // MARK: - Not-a-CW20 (nil) outcomes

    func testCw20TokenInfoReturnsNilOnLcdError() async throws {
        // A non-CW20 contract (or a wallet address) makes the LCD answer the
        // smart query with an error status — the resolver maps that to nil so
        // the caller can surface its not-found UX.
        let stub = Cw20ScriptedHTTPClient()
        stub.result = .httpError(500)
        let resolver = CosmosTokenMetadataResolver(httpClient: stub)

        let info = try await resolver.cw20TokenInfo(chain: .terra, contractAddress: astroContract)

        XCTAssertNil(info)
    }

    func testCw20TokenInfoReturnsNilForUnparseableReply() async throws {
        // A 200 whose body doesn't decode as a token_info reply is a contract
        // answering with something else — not a CW20 token, not a transport
        // failure.
        let stub = Cw20ScriptedHTTPClient()
        stub.result = .json(["data": 42])
        let resolver = CosmosTokenMetadataResolver(httpClient: stub)

        let info = try await resolver.cw20TokenInfo(chain: .terra, contractAddress: astroContract)

        XCTAssertNil(info)
    }

    func testCw20TokenInfoReturnsNilForMissingSymbol() async throws {
        let stub = Cw20ScriptedHTTPClient()
        stub.result = .json(["data": ["name": "Some Contract State", "decimals": 6]])
        let resolver = CosmosTokenMetadataResolver(httpClient: stub)

        let info = try await resolver.cw20TokenInfo(chain: .terra, contractAddress: astroContract)

        XCTAssertNil(info)
    }

    func testCw20TokenInfoReturnsNilForBlankSymbol() async throws {
        let stub = Cw20ScriptedHTTPClient()
        stub.result = .json(["data": ["name": "Blank", "symbol": "  ", "decimals": 6]])
        let resolver = CosmosTokenMetadataResolver(httpClient: stub)

        let info = try await resolver.cw20TokenInfo(chain: .terra, contractAddress: astroContract)

        XCTAssertNil(info)
    }

    func testCw20TokenInfoReturnsNilForMissingDecimals() async throws {
        let stub = Cw20ScriptedHTTPClient()
        stub.result = .json(["data": ["name": "No Decimals", "symbol": "NODEC"]])
        let resolver = CosmosTokenMetadataResolver(httpClient: stub)

        let info = try await resolver.cw20TokenInfo(chain: .terra, contractAddress: astroContract)

        XCTAssertNil(info)
    }

    func testCw20TokenInfoReturnsNilForNegativeDecimals() async throws {
        let stub = Cw20ScriptedHTTPClient()
        stub.result = .json(["data": ["name": "Bad", "symbol": "BAD", "decimals": -1]])
        let resolver = CosmosTokenMetadataResolver(httpClient: stub)

        let info = try await resolver.cw20TokenInfo(chain: .terra, contractAddress: astroContract)

        XCTAssertNil(info)
    }

    func testCw20TokenInfoReturnsNilForExcessiveDecimals() async throws {
        // Contract-controlled decimals feed BigInt(10).power(decimals) in
        // downstream formatting; a hostile contract must not smuggle in a
        // huge exponent (same 0...36 bound as the ERC-20 metadata resolver).
        let stub = Cw20ScriptedHTTPClient()
        stub.result = .json(["data": ["name": "Hostile", "symbol": "EVIL", "decimals": 65535]])
        let resolver = CosmosTokenMetadataResolver(httpClient: stub)

        let info = try await resolver.cw20TokenInfo(chain: .terra, contractAddress: astroContract)

        XCTAssertNil(info)
    }

    func testCw20TokenInfoReturnsNilForUnsupportedChain() async throws {
        // Chains without a Cosmos LCD config can't run a wasm smart query;
        // the resolver must bail out without touching the network.
        let stub = Cw20ScriptedHTTPClient()
        stub.result = .success(name: "X", symbol: "X", decimals: 6)
        let resolver = CosmosTokenMetadataResolver(httpClient: stub)

        let info = try await resolver.cw20TokenInfo(chain: .ethereum, contractAddress: astroContract)

        XCTAssertNil(info)
        XCTAssertEqual(stub.callCount, 0)
    }

    // MARK: - Transport failures (thrown)

    func testCw20TokenInfoThrowsOnRateLimit() async {
        // Rate limiting says nothing about the address; it must NOT collapse
        // into not-found. The typed 429 propagates so the custom-token screen
        // can show its dedicated rate-limit copy.
        let stub = Cw20ScriptedHTTPClient()
        stub.result = .httpError(429)
        let resolver = CosmosTokenMetadataResolver(httpClient: stub)

        do {
            _ = try await resolver.cw20TokenInfo(chain: .terra, contractAddress: astroContract)
            XCTFail("Expected a thrown rate-limit error")
        } catch HTTPError.statusCode(let code, _) {
            XCTAssertEqual(code, 429)
        } catch {
            XCTFail("Expected HTTPError.statusCode(429), got \(error)")
        }
    }

    func testCw20TokenInfoThrowsOnRetryableServerStatus() async {
        // Gateway/overload statuses (502/503/504/408) are transient — they
        // must propagate as retryable errors, not collapse into not-found.
        // (500 stays not-found: Terra LCDs use it for semantic smart-query
        // failures on wallet addresses / non-CW20 contracts.)
        let stub = Cw20ScriptedHTTPClient()
        stub.result = .httpError(503)
        let resolver = CosmosTokenMetadataResolver(httpClient: stub)

        do {
            _ = try await resolver.cw20TokenInfo(chain: .terra, contractAddress: astroContract)
            XCTFail("Expected a thrown transient-status error")
        } catch HTTPError.statusCode(let code, _) {
            XCTAssertEqual(code, 503)
        } catch {
            XCTFail("Expected HTTPError.statusCode(503), got \(error)")
        }
    }

    func testCw20TokenInfoThrowsOnNetworkError() async {
        // Network-layer failures (offline, DNS, connection reset) are
        // transient — propagate them so the screen shows the error and offers
        // retry instead of declaring the token nonexistent.
        let stub = Cw20ScriptedHTTPClient()
        stub.result = .transportError(HTTPError.networkError(URLError(.notConnectedToInternet)))
        let resolver = CosmosTokenMetadataResolver(httpClient: stub)

        do {
            _ = try await resolver.cw20TokenInfo(chain: .terra, contractAddress: astroContract)
            XCTFail("Expected a thrown network error")
        } catch HTTPError.networkError {
            // expected
        } catch {
            XCTFail("Expected HTTPError.networkError, got \(error)")
        }
    }

    // MARK: - Cache semantics

    func testCw20TokenInfoCachesSuccessfulLookup() async throws {
        let stub = Cw20ScriptedHTTPClient()
        stub.result = .success(name: "Astroport", symbol: "ASTRO", decimals: 6)
        let resolver = CosmosTokenMetadataResolver(httpClient: stub)

        let first = try await resolver.cw20TokenInfo(chain: .terra, contractAddress: astroContract)
        let second = try await resolver.cw20TokenInfo(chain: .terra, contractAddress: astroContract)

        XCTAssertEqual(first, second)
        XCTAssertEqual(stub.callCount, 1, "Second lookup must be served from the cache")
    }

    func testCw20TokenInfoEvictsCacheOnTransportFailure() async throws {
        // A transient LCD failure must NOT poison the cache: after a thrown
        // transport error the next call retries (and succeeds once the LCD
        // recovers).
        let stub = Cw20ScriptedHTTPClient()
        stub.result = .transportError(HTTPError.timeout)
        let resolver = CosmosTokenMetadataResolver(httpClient: stub)

        do {
            _ = try await resolver.cw20TokenInfo(chain: .terra, contractAddress: astroContract)
            XCTFail("Expected a thrown transport error")
        } catch {
            // expected — the entry must have been evicted
        }

        stub.result = .success(name: "Astroport", symbol: "ASTRO", decimals: 6)
        let second = try await resolver.cw20TokenInfo(chain: .terra, contractAddress: astroContract)

        XCTAssertEqual(second?.symbol, "ASTRO", "Cache eviction on error must let the retry succeed")
    }

    func testCw20TokenInfoEvictsCacheOnNotFound() async throws {
        // A not-found verdict is not cached either: if the LCD (or a flaky
        // proxy) wrongly 500s once, the next attempt retries.
        let stub = Cw20ScriptedHTTPClient()
        stub.result = .httpError(500)
        let resolver = CosmosTokenMetadataResolver(httpClient: stub)

        let first = try await resolver.cw20TokenInfo(chain: .terra, contractAddress: astroContract)
        XCTAssertNil(first)

        stub.result = .success(name: "Astroport", symbol: "ASTRO", decimals: 6)
        let second = try await resolver.cw20TokenInfo(chain: .terra, contractAddress: astroContract)

        XCTAssertEqual(second?.symbol, "ASTRO", "Cache eviction on nil must let the retry succeed")
    }
}

// MARK: - Stub HTTP client

/// Scripted HTTP client for CW20 `token_info` lookups. Responses are
/// assembled as JSON and run through the production `JSONDecoder`, so the
/// test exercises the real decode path — including the protocol extension's
/// `HTTPError.decodingFailed` wrapping.
private final class Cw20ScriptedHTTPClient: HTTPClientProtocol, @unchecked Sendable {

    enum ScriptedResult {
        case success(name: String, symbol: String, decimals: Int)
        case json([String: Any])
        case httpError(Int)
        case transportError(Error)
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
        case .transportError(let error):
            throw error
        }

        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded: T
        do {
            decoded = try JSONDecoder().decode(T.self, from: data)
        } catch {
            // Mirror the production HTTPClientProtocol extension, which wraps
            // decode failures of a 200 response in `.decodingFailed`.
            throw HTTPError.decodingFailed(error)
        }
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
