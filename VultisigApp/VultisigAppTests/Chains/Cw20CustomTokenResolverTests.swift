//
//  Cw20CustomTokenResolverTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

final class Cw20CustomTokenResolverTests: XCTestCase {

    // ASTRO on Terra — a 32-byte CW20 contract address (post-migration shape).
    private let astroContract = "terra1nsuqsk6kh58ulczatwev87ttq2z6r3pusulg9r24mfj2fvtzd4uq3exn26"
    // ASTROC on Terra Classic — a 20-byte contract, shape-identical to a wallet address.
    private let astrocContract = "terra1xj49zyqrwpv5k928jwfpfy2ha668nwdgkwlrg3"

    // MARK: - Input validation

    func testIsValidInputAcceptsLongContractOnTerra() {
        XCTAssertTrue(Cw20CustomTokenResolver.isValidInput(astroContract, chain: .terra))
    }

    func testIsValidInputAcceptsLongContractOnTerraClassic() {
        XCTAssertTrue(Cw20CustomTokenResolver.isValidInput(astroContract, chain: .terraClassic))
    }

    func testIsValidInputAcceptsShortContractOnTerraClassic() {
        // Pre-migration Terra Classic contracts are 20-byte bech32 — the same
        // shape as wallet addresses. They must pass; only the LCD query can
        // tell a contract from a wallet.
        XCTAssertTrue(Cw20CustomTokenResolver.isValidInput(astrocContract, chain: .terraClassic))
    }

    func testIsValidInputRejectsNonTerraChains() {
        XCTAssertFalse(Cw20CustomTokenResolver.isValidInput(astroContract, chain: .gaiaChain))
        XCTAssertFalse(Cw20CustomTokenResolver.isValidInput(astroContract, chain: .osmosis))
        XCTAssertFalse(Cw20CustomTokenResolver.isValidInput(astroContract, chain: .ethereum))
    }

    func testIsValidInputRejectsForeignAddressShapes() {
        XCTAssertFalse(
            Cw20CustomTokenResolver.isValidInput("0x1a44076050125825900e736c501f859c50fE728c", chain: .terra)
        )
        XCTAssertFalse(
            Cw20CustomTokenResolver.isValidInput("thor1z53wwe7md6cewz9sqwqzn0aavpaun0gw0exn2r", chain: .terra)
        )
    }

    func testIsValidInputRejectsBankDenoms() {
        XCTAssertFalse(
            Cw20CustomTokenResolver.isValidInput(
                "ibc/8D8A7F7253615E5F76CB6252A1E1BD921D5EDB7BBAAF8913FB1C77FF125D9995",
                chain: .terra
            )
        )
        XCTAssertFalse(
            Cw20CustomTokenResolver.isValidInput("factory/terra1abc/uxyz", chain: .terra)
        )
        XCTAssertFalse(Cw20CustomTokenResolver.isValidInput("uusd", chain: .terraClassic))
    }

    func testIsValidInputRejectsMalformedInput() {
        XCTAssertFalse(Cw20CustomTokenResolver.isValidInput("", chain: .terra))
        XCTAssertFalse(Cw20CustomTokenResolver.isValidInput("terra1", chain: .terra))
        XCTAssertFalse(Cw20CustomTokenResolver.isValidInput("terra1tooshort", chain: .terra))
        XCTAssertFalse(
            Cw20CustomTokenResolver.isValidInput(astroContract.uppercased(), chain: .terra),
            "Bech32 is lowercase-only"
        )
        XCTAssertFalse(
            Cw20CustomTokenResolver.isValidInput(" \(astroContract)", chain: .terra),
            "Whitespace-padded input is rejected, matching the other chains' validators"
        )
        XCTAssertFalse(
            Cw20CustomTokenResolver.isValidInput("terra1" + String(repeating: "a", count: 81), chain: .terra)
        )
    }

    // MARK: - Resolution

    func testResolveUnknownContractBuildsCoinMetaFromTokenInfo() async throws {
        let stub = Cw20ResolverScriptedHTTPClient()
        stub.result = .success(name: "Eris Amplified LUNA", symbol: "ampLUNA", decimals: 6)
        let metadataResolver = CosmosTokenMetadataResolver(httpClient: stub)
        // A contract that is NOT in the curated TokensStore catalog.
        let contract = "terra1ecgazyd0waaj3g7l9cmy5gulhxkps2gmxu9ghducvuypjq68mq2s5lvsct"

        let meta = try await Cw20CustomTokenResolver.resolve(
            contractAddress: contract,
            chain: .terra,
            metadataResolver: metadataResolver
        )

        XCTAssertEqual(
            meta,
            CoinMeta(
                chain: .terra,
                ticker: "ampLUNA",
                logo: "",
                decimals: 6,
                priceProviderId: "",
                contractAddress: contract,
                isNativeToken: false
            )
        )
    }

    func testResolveCuratedContractPrefersTokensStoreEntry() async throws {
        // Pasting a catalog token's contract must keep the curated logo and
        // priceProviderId instead of the bare LCD metadata.
        let stub = Cw20ResolverScriptedHTTPClient()
        stub.result = .success(name: "Astroport", symbol: "ASTRO", decimals: 6)
        let metadataResolver = CosmosTokenMetadataResolver(httpClient: stub)

        let meta = try await Cw20CustomTokenResolver.resolve(
            contractAddress: astroContract,
            chain: .terra,
            metadataResolver: metadataResolver
        )

        XCTAssertEqual(meta?.ticker, "ASTRO")
        XCTAssertEqual(meta?.logo, "terra-astroport")
        XCTAssertEqual(meta?.priceProviderId, "astroport-fi")
        XCTAssertEqual(meta?.contractAddress, astroContract)
    }

    func testResolveReturnsNilWhenLcdRejectsQuery() async throws {
        // A wallet address / non-CW20 contract makes the LCD reject the
        // token_info query — the resolver must answer nil (not-found UX).
        let stub = Cw20ResolverScriptedHTTPClient()
        stub.result = .httpError(500)
        let metadataResolver = CosmosTokenMetadataResolver(httpClient: stub)

        let meta = try await Cw20CustomTokenResolver.resolve(
            contractAddress: astrocContract,
            chain: .terraClassic,
            metadataResolver: metadataResolver
        )

        XCTAssertNil(meta)
    }

    func testResolveReturnsNilWithoutNetworkCallForInvalidInput() async throws {
        let stub = Cw20ResolverScriptedHTTPClient()
        stub.result = .success(name: "X", symbol: "X", decimals: 6)
        let metadataResolver = CosmosTokenMetadataResolver(httpClient: stub)

        let meta = try await Cw20CustomTokenResolver.resolve(
            contractAddress: "0x1a44076050125825900e736c501f859c50fE728c",
            chain: .terra,
            metadataResolver: metadataResolver
        )

        XCTAssertNil(meta)
        XCTAssertEqual(stub.callCount, 0, "Invalid input must short-circuit before any LCD call")
    }

    func testResolvePropagatesRateLimitError() async {
        // Rate limiting must NOT collapse into not-found: the typed 429
        // propagates so CustomTokenScreen shows its RateLimitError copy
        // (which also hides the retry button).
        let stub = Cw20ResolverScriptedHTTPClient()
        stub.result = .httpError(429)
        let metadataResolver = CosmosTokenMetadataResolver(httpClient: stub)

        do {
            _ = try await Cw20CustomTokenResolver.resolve(
                contractAddress: astroContract,
                chain: .terra,
                metadataResolver: metadataResolver
            )
            XCTFail("Expected a thrown rate-limit error")
        } catch HTTPError.statusCode(let code, _) {
            XCTAssertEqual(code, 429)
        } catch {
            XCTFail("Expected HTTPError.statusCode(429), got \(error)")
        }
    }

    func testResolvePropagatesNetworkError() async {
        // Transient network failures surface as errors (screen shows the
        // message + retry), not as a false "token not found" verdict.
        let stub = Cw20ResolverScriptedHTTPClient()
        stub.result = .transportError(HTTPError.networkError(URLError(.notConnectedToInternet)))
        let metadataResolver = CosmosTokenMetadataResolver(httpClient: stub)

        do {
            _ = try await Cw20CustomTokenResolver.resolve(
                contractAddress: astroContract,
                chain: .terra,
                metadataResolver: metadataResolver
            )
            XCTFail("Expected a thrown network error")
        } catch HTTPError.networkError {
            // expected
        } catch {
            XCTFail("Expected HTTPError.networkError, got \(error)")
        }
    }
}

// MARK: - Stub HTTP client

/// Scripted HTTP client for CW20 resolution tests: answers every request
/// with one scripted result, running success payloads through the real
/// `JSONDecoder` path.
private final class Cw20ResolverScriptedHTTPClient: HTTPClientProtocol, @unchecked Sendable {

    enum ScriptedResult {
        case success(name: String, symbol: String, decimals: Int)
        case httpError(Int)
        case transportError(Error)
    }

    var result: ScriptedResult = .httpError(500)

    private let queue = DispatchQueue(label: "Cw20ResolverScriptedHTTPClient.queue")
    private var _callCount = 0

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
        guard target is CosmosAPI else {
            throw HTTPError.invalidResponse
        }
        queue.sync { _callCount += 1 }

        switch result {
        case .success(let name, let symbol, let decimals):
            let json: [String: Any] = [
                "data": ["name": name, "symbol": symbol, "decimals": decimals, "total_supply": "1000000"]
            ]
            let data = try JSONSerialization.data(withJSONObject: json)
            let decoded = try JSONDecoder().decode(T.self, from: data)
            let response = HTTPURLResponse(
                url: URL(string: "https://test.local")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return HTTPResponse(data: decoded, response: response)
        case .httpError(let code):
            throw HTTPError.statusCode(code, nil)
        case .transportError(let error):
            throw error
        }
    }

    func requestEmpty(_: TargetType) async throws -> HTTPResponse<EmptyResponse> {
        throw HTTPError.invalidResponse
    }
    // swiftlint:enable async_without_await
}
