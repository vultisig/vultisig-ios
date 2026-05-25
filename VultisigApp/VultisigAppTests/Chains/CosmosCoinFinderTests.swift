//
//  CosmosCoinFinderTests.swift
//  VultisigAppTests
//
//  Pins the Terra / TerraClassic bank-denom auto-discovery contract against
//  the SDK reference resolver in `vultisig-sdk/packages/core/chain/coin/
//  find/resolvers/cosmos.ts` plus `metadata/resolvers/cosmos.ts`. The five
//  scenarios assert byte-for-byte parity with the SDK test suite — adding
//  / removing a case here requires the same change on the SDK side.
//

@testable import VultisigApp
import XCTest

final class CosmosCoinFinderTests: XCTestCase {

    // MARK: - Allowlist

    func testAllowlistedChainsMatchSdkAutoDiscoveryChains() {
        XCTAssertTrue(CosmosCoinFinder.allowlistedChains.contains(.terra))
        XCTAssertTrue(CosmosCoinFinder.allowlistedChains.contains(.terraClassic))
        // Per the SDK `AUTO_DISCOVERY_CHAINS` set, no other Cosmos chains
        // ship auto-discovery. Adding one requires lockstep SDK + iOS work.
        XCTAssertEqual(CosmosCoinFinder.allowlistedChains.count, 2)
    }

    func testGaiaChainNotAllowlistedReturnsEmptyWithoutBalanceFetch() async throws {
        // Scenario 5: non-allowlisted Cosmos chain returns `[]` and must NOT
        // hit the LCD. We use a stub that throws on any call so the test
        // would fail if the implementation made a network request.
        let stub = ScriptedHTTPClient()
        let finder = CosmosCoinFinder(httpClient: stub, metadataResolver: makeIsolatedResolver(client: stub))
        let result = try await finder.discoverBankDenoms(chain: .gaiaChain, address: "cosmos1abc")
        XCTAssertEqual(result, [])
        XCTAssertEqual(stub.totalCallCount, 0)
    }

    // MARK: - Decimal extraction (pure)

    func testDecimalsFromMetaPicksDisplayUnit() {
        // Most Cosmos denoms expose `display = "luna"` at exponent 6.
        let meta = CosmosDenomMetadata(
            base: "uluna",
            symbol: "LUNA",
            display: "luna",
            denomUnits: [
                CosmosDenomUnit(denom: "uluna", exponent: 0),
                CosmosDenomUnit(denom: "luna", exponent: 6)
            ]
        )
        XCTAssertEqual(CosmosTokenMetadataResolver.decimalsFromMeta(meta), 6)
    }

    func testDecimalsFromMetaHandlesEighteenDecimalIbcDenom() {
        // Scenario 2: ETH-backed IBC denoms on Terra carry exponent 18 in
        // metadata. The wallet must NOT default to 6 just because LUNA is.
        let meta = CosmosDenomMetadata(
            base: "ibc/eth-weth",
            symbol: "WETH",
            display: "weth",
            denomUnits: [
                CosmosDenomUnit(denom: "ibc/eth-weth", exponent: 0),
                CosmosDenomUnit(denom: "weth", exponent: 18)
            ]
        )
        XCTAssertEqual(CosmosTokenMetadataResolver.decimalsFromMeta(meta), 18)
    }

    func testDecimalsFromMetaReturnsNilWhenDisplayMissing() {
        // Some Terra IBC denoms ship metadata with no `display`. The SDK
        // returns null in that case so the caller can route to the IBC
        // trace recursion or the hidden tier — iOS must do the same.
        let meta = CosmosDenomMetadata(
            base: "uluna",
            symbol: nil,
            display: nil,
            denomUnits: [CosmosDenomUnit(denom: "luna", exponent: 6)]
        )
        XCTAssertNil(CosmosTokenMetadataResolver.decimalsFromMeta(meta))
    }

    func testDecimalsFromMetaReturnsNilWhenNoUnitMatchesDisplay() {
        // Display is set but no `denom_units` entry matches it. Falls
        // through to symbol; if symbol also misses, returns nil so the
        // caller can fall through to the hide-with-fee-decimals tier.
        let meta = CosmosDenomMetadata(
            base: "uluna",
            symbol: nil,
            display: "luna",
            denomUnits: [CosmosDenomUnit(denom: "atom", exponent: 6)]
        )
        XCTAssertNil(CosmosTokenMetadataResolver.decimalsFromMeta(meta))
    }

    // MARK: - Ticker derivation (pure)

    func testDeriveTickerPrefersSymbol() {
        let meta = CosmosDenomMetadata(base: "x", symbol: "USTC", display: "ustc", denomUnits: nil)
        XCTAssertEqual(CosmosTokenMetadataResolver.deriveTicker(denom: "uusd", meta: meta), "USTC")
    }

    func testDeriveTickerFallsBackToDisplayWhenSymbolEmpty() {
        let meta = CosmosDenomMetadata(base: "x", symbol: "", display: "USTC", denomUnits: nil)
        XCTAssertEqual(CosmosTokenMetadataResolver.deriveTicker(denom: "uusd", meta: meta), "USTC")
    }

    func testDeriveTickerFactoryDenomStripsLeadingU() {
        // `factory/<minter>/uXYZ` → `XYZ` per the SDK's leading-`u` strip.
        let ticker = CosmosTokenMetadataResolver.deriveTicker(
            denom: "factory/terra1abc/uxyz",
            meta: nil
        )
        XCTAssertEqual(ticker, "xyz")
    }

    func testDeriveTickerFactoryDenomKeepsNonULeading() {
        // `factory/<minter>/foo` → `foo`. Only a literal leading `u` is
        // stripped; "f" stays.
        let ticker = CosmosTokenMetadataResolver.deriveTicker(
            denom: "factory/terra1abc/foo",
            meta: nil
        )
        XCTAssertEqual(ticker, "foo")
    }

    func testDeriveTickerXStakingPrefix() {
        // `x/staking-tcy` → `Stcy` per the SDK's THORChain x-staking rule.
        let ticker = CosmosTokenMetadataResolver.deriveTicker(
            denom: "x/staking-tcy",
            meta: nil
        )
        XCTAssertEqual(ticker, "Stcy")
    }

    func testDeriveTickerXPrefixGenericReturnsLastComponent() {
        let ticker = CosmosTokenMetadataResolver.deriveTicker(denom: "x/ruji", meta: nil)
        XCTAssertEqual(ticker, "ruji")
    }

    func testDeriveTickerFallsThroughToFullDenomWhenNoRuleMatches() {
        let ticker = CosmosTokenMetadataResolver.deriveTicker(denom: "uatom", meta: nil)
        XCTAssertEqual(ticker, "uatom")
    }

    // MARK: - Fee-denom + fee-decimals table

    func testFeeDenomForTerraIsUluna() {
        XCTAssertEqual(CosmosCoinFinder.feeDenom(for: .terra), "uluna")
        XCTAssertEqual(CosmosCoinFinder.feeDenom(for: .terraClassic), "uluna")
    }

    func testFeeDecimalsForTerraIsSix() {
        XCTAssertEqual(CosmosCoinFinder.feeDecimals(for: .terra), 6)
        XCTAssertEqual(CosmosCoinFinder.feeDecimals(for: .terraClassic), 6)
    }

    // MARK: - Discovery: full flow with stubbed HTTP

    func testTerraClassicUusdResolvesToUstcViaTokensStore() async throws {
        // Scenario 1: TerraClassic + `uusd` resolves to USTC via the
        // curated `TokensStore` entry (logo + priceProviderId =
        // "terrausd"). No metadata HTTP call expected — the curated
        // lookup short-circuits before the LCD is hit.
        let stub = ScriptedHTTPClient()
        stub.balances = [
            ("uluna", "1000"),
            ("uusd", "5000")
        ]
        let finder = CosmosCoinFinder(httpClient: stub, metadataResolver: makeIsolatedResolver(client: stub))
        let result = try await finder.discoverBankDenoms(
            chain: .terraClassic,
            address: "terra1classic"
        )

        XCTAssertEqual(result.count, 1, "uluna is the fee denom and must be filtered out")
        let ustc = try XCTUnwrap(result.first)
        XCTAssertEqual(ustc.denom, "uusd")
        XCTAssertEqual(ustc.ticker, "USTC")
        XCTAssertEqual(ustc.decimals, 6)
        XCTAssertEqual(ustc.priceProviderId, "terrausd")
        XCTAssertFalse(ustc.isHidden)
        XCTAssertFalse(ustc.logo.isEmpty, "TokensStore curated entry must supply a logo")
    }

    func testTerraIbcDenomWithEighteenDecimalMetadata() async throws {
        // Scenario 2: Terra + an IBC denom that ships metadata with
        // exponent 18 (e.g. ETH/WETH bridged through). Decimals must
        // come from the metadata, not the chain-fee fallback.
        let ibcWeth = "ibc/wethhash"
        let stub = ScriptedHTTPClient()
        stub.balances = [
            ("uluna", "1000"),
            (ibcWeth, "1000000000000000000")
        ]
        stub.denomMetadataPayloads[ibcWeth] = ScriptedHTTPClient.MetaPayload(
            symbol: "WETH",
            display: "weth",
            unitDenom: "weth",
            exponent: 18
        )

        let finder = CosmosCoinFinder(
            httpClient: stub,
            metadataResolver: makeIsolatedResolver(client: stub)
        )
        let result = try await finder.discoverBankDenoms(chain: .terra, address: "terra1abc")
        XCTAssertEqual(result.count, 1)
        let weth = try XCTUnwrap(result.first)
        XCTAssertEqual(weth.denom, ibcWeth)
        XCTAssertEqual(weth.ticker, "WETH")
        XCTAssertEqual(weth.decimals, 18, "Must NOT default to 6 just because LUNA is 6")
        XCTAssertFalse(weth.isHidden)
    }

    func testTerraFactoryDenomWithoutMetadataIsHiddenWithDerivedTicker() async throws {
        // Scenario 3: Terra + factory denom with no metadata → hidden,
        // ticker derived from the factory tail (leading `u` stripped),
        // decimals fall back to the chain fee-coin (6). Must NOT be dropped.
        let factoryDenom = "factory/terra1minter/uxyz"
        let stub = ScriptedHTTPClient()
        stub.balances = [
            ("uluna", "1000"),
            (factoryDenom, "42")
        ]
        // No metadata configured for the factory denom — both direct and
        // list-fetch will yield empty.

        let finder = CosmosCoinFinder(
            httpClient: stub,
            metadataResolver: makeIsolatedResolver(client: stub)
        )
        let result = try await finder.discoverBankDenoms(chain: .terra, address: "terra1abc")
        XCTAssertEqual(result.count, 1, "Hidden denoms must be surfaced, not dropped")
        let xyz = try XCTUnwrap(result.first)
        XCTAssertEqual(xyz.denom, factoryDenom)
        XCTAssertEqual(xyz.ticker, "xyz")
        XCTAssertEqual(xyz.decimals, 6)
        XCTAssertTrue(xyz.isHidden)
    }

    func testTerraIbcTraceFallbackPropagatesHidden() async throws {
        // Scenario 4: Terra + IBC denom whose direct metadata returns
        // nothing but whose denom_traces lookup yields a base denom. Even
        // if the base denom resolves to metadata, the discovered token
        // must carry `isHidden = true` because the wallet only knows it
        // through the trace recursion.
        let ibcHash = "ABC123"
        let ibcDenom = "ibc/\(ibcHash)"
        let baseDenom = "uatom"
        let stub = ScriptedHTTPClient()
        stub.balances = [
            ("uluna", "1000"),
            (ibcDenom, "999")
        ]
        stub.ibcTracePayloads[ibcHash] = ScriptedHTTPClient.TracePayload(
            path: "transfer/channel-0",
            baseDenom: baseDenom
        )
        stub.denomMetadataPayloads[baseDenom] = ScriptedHTTPClient.MetaPayload(
            symbol: "ATOM",
            display: "atom",
            unitDenom: "atom",
            exponent: 6
        )

        let finder = CosmosCoinFinder(
            httpClient: stub,
            metadataResolver: makeIsolatedResolver(client: stub)
        )
        let result = try await finder.discoverBankDenoms(chain: .terra, address: "terra1abc")
        XCTAssertEqual(result.count, 1)
        let atom = try XCTUnwrap(result.first)
        XCTAssertEqual(atom.denom, ibcDenom, "Discovered denom must be the on-chain ibc/<hash> id")
        XCTAssertEqual(atom.ticker, "ATOM")
        XCTAssertEqual(atom.decimals, 6)
        XCTAssertTrue(atom.isHidden, "IBC trace path always sets isHidden = true")
    }

    // MARK: - Cache contract

    func testMetadataCacheCoalescesConcurrentLookupsForSameDenom() async {
        // Two concurrent callers for the same denom must share one HTTP
        // round-trip. The SDK's promise-based cache pins this to exactly
        // 1 — iOS mirrors the contract via `Task`-cell caching.
        let stub = ScriptedHTTPClient()
        let denom = "factory/terra1abc/uxyz"
        stub.denomMetadataPayloads[denom] = ScriptedHTTPClient.MetaPayload(
            symbol: "XYZ",
            display: "xyz",
            unitDenom: "xyz",
            exponent: 6
        )
        let resolver = makeIsolatedResolver(client: stub)

        async let first = resolver.denomMetadata(chain: .terra, denom: denom)
        async let second = resolver.denomMetadata(chain: .terra, denom: denom)
        let (a, b) = await (first, second)

        XCTAssertEqual(a?.symbol, "XYZ")
        XCTAssertEqual(b?.symbol, "XYZ")
        XCTAssertEqual(
            stub.denomMetadataCallCount(for: denom),
            1,
            "Concurrent in-flight requests must coalesce on one HTTP call"
        )
    }

    func testMetadataCacheEvictsEntryOnNetworkError() async {
        // A transient LCD failure must NOT poison the cache for 24h. After
        // a failed call, the next call should retry (and succeed once the
        // stub starts returning data).
        let stub = ScriptedHTTPClient()
        let denom = "factory/terra1abc/uxyz"
        stub.shouldFailAllRequests = true
        let resolver = makeIsolatedResolver(client: stub)

        let first = await resolver.denomMetadata(chain: .terra, denom: denom)
        XCTAssertNil(first, "First call returns nil because the LCD is failing")

        // LCD comes back; the cache must have been evicted so the second
        // call actually retries instead of returning the cached nil.
        stub.shouldFailAllRequests = false
        stub.denomMetadataPayloads[denom] = ScriptedHTTPClient.MetaPayload(
            symbol: "XYZ",
            display: "xyz",
            unitDenom: "xyz",
            exponent: 6
        )

        let second = await resolver.denomMetadata(chain: .terra, denom: denom)
        XCTAssertEqual(second?.symbol, "XYZ", "Cache eviction on error must let the retry succeed")
    }

    func testIbcDenomTraceShortCircuitsForNonIbcDenom() async {
        // The SDK's resolver checks the `ibc/` prefix before issuing a
        // trace lookup. iOS must do the same — calling `ibcDenomTrace`
        // with `uatom` must return nil WITHOUT a network call.
        let stub = ScriptedHTTPClient()
        let resolver = makeIsolatedResolver(client: stub)

        let result = await resolver.ibcDenomTrace(chain: .terra, denom: "uatom")
        XCTAssertNil(result)
        XCTAssertEqual(
            stub.ibcTraceCallCount,
            0,
            "Non-IBC denoms must not trigger a denom_traces lookup"
        )
    }

    // MARK: - Test helpers

    private func makeIsolatedResolver(client: HTTPClientProtocol) -> CosmosTokenMetadataResolver {
        // Each test gets its own resolver to keep the 24h cache from
        // leaking across cases.
        CosmosTokenMetadataResolver(httpClient: client)
    }
}

// MARK: - Stub HTTP client

/// Scripted HTTP client driven entirely by JSON-encoded payloads. The
/// service code under test goes through `JSONDecoder` so the cleanest way
/// to script responses is to assemble JSON dicts and let the production
/// decoder do the work — keeps the test free of class-init coupling to
/// `CosmosBalanceResponse` / `CosmosIbcDenomTrace`.
private final class ScriptedHTTPClient: HTTPClientProtocol, @unchecked Sendable {

    struct MetaPayload {
        let symbol: String
        let display: String
        let unitDenom: String
        let exponent: Int
    }

    struct TracePayload {
        let path: String
        let baseDenom: String
    }

    // Scripted payloads — assigned by the test before calling the service.
    var balances: [(denom: String, amount: String)] = []
    var denomMetadataPayloads: [String: MetaPayload] = [:]
    var ibcTracePayloads: [String: TracePayload] = [:]
    var shouldFailAllRequests = false

    private let queue = DispatchQueue(label: "ScriptedHTTPClient.queue")
    private var _denomMetadataCalls: [String: Int] = [:]
    private var _ibcTraceCalls = 0
    private var _totalCalls = 0

    func denomMetadataCallCount(for denom: String) -> Int {
        queue.sync { _denomMetadataCalls[denom] ?? 0 }
    }

    var ibcTraceCallCount: Int {
        queue.sync { _ibcTraceCalls }
    }

    var totalCallCount: Int {
        queue.sync { _totalCalls }
    }

    // swiftlint:disable async_without_await
    func request(_: TargetType) async throws -> HTTPResponse<Data> {
        throw HTTPError.invalidResponse
    }

    func request<T: Decodable>(
        _ target: TargetType,
        responseType _: T.Type
    ) async throws -> HTTPResponse<T> {
        queue.sync { _totalCalls += 1 }

        if shouldFailAllRequests {
            throw HTTPError.statusCode(503, nil)
        }

        guard let api = target as? CosmosAPI else {
            throw HTTPError.invalidResponse
        }

        let stubUrl = HTTPURLResponse(
            url: URL(string: "https://test.local")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        switch api.endpoint {
        case .balance, .spendableBalance:
            let json: [String: Any] = [
                "balances": balances.map { ["denom": $0.denom, "amount": $0.amount] },
                "pagination": ["next_key": NSNull(), "total": "\(balances.count)"]
            ]
            let data = try JSONSerialization.data(withJSONObject: json)
            let decoded = try JSONDecoder().decode(T.self, from: data)
            return HTTPResponse(data: decoded, response: stubUrl)

        case .denomMetadata(let denom):
            queue.sync { _denomMetadataCalls[denom, default: 0] += 1 }
            // No payload → return an empty metadata object so the resolver
            // falls through to the list endpoint (which we also leave empty,
            // forcing the hidden-tier fallback).
            let metadataJson: Any
            if let payload = denomMetadataPayloads[denom] {
                metadataJson = Self.metadataDict(denom: denom, payload: payload)
            } else {
                metadataJson = NSNull()
            }
            let envelope: [String: Any] = ["metadata": metadataJson]
            let data = try JSONSerialization.data(withJSONObject: envelope)
            let decoded = try JSONDecoder().decode(T.self, from: data)
            return HTTPResponse(data: decoded, response: stubUrl)

        case .allDenomsMetadata:
            // Production list endpoint returns every registered denom; the
            // stub returns the union of `denomMetadataPayloads` so a
            // direct-fetch miss can still surface here. Tests that need
            // the list path empty should leave the payload map empty.
            let metadatas = denomMetadataPayloads.map { denom, payload in
                Self.metadataDict(denom: denom, payload: payload)
            }
            let envelope: [String: Any] = ["metadatas": metadatas]
            let data = try JSONSerialization.data(withJSONObject: envelope)
            let decoded = try JSONDecoder().decode(T.self, from: data)
            return HTTPResponse(data: decoded, response: stubUrl)

        case .ibcDenomTrace(let hash):
            queue.sync { _ibcTraceCalls += 1 }
            let envelope: [String: Any]
            if let payload = ibcTracePayloads[hash] {
                envelope = ["denom_trace": ["path": payload.path, "base_denom": payload.baseDenom]]
            } else {
                envelope = [:]
            }
            let data = try JSONSerialization.data(withJSONObject: envelope)
            let decoded = try JSONDecoder().decode(T.self, from: data)
            return HTTPResponse(data: decoded, response: stubUrl)

        default:
            throw HTTPError.invalidResponse
        }
    }

    func requestEmpty(_: TargetType) async throws -> HTTPResponse<EmptyResponse> {
        throw HTTPError.invalidResponse
    }
    // swiftlint:enable async_without_await

    private static func metadataDict(denom: String, payload: MetaPayload) -> [String: Any] {
        [
            "base": denom,
            "symbol": payload.symbol,
            "display": payload.display,
            "denom_units": [
                ["denom": denom, "exponent": 0],
                ["denom": payload.unitDenom, "exponent": payload.exponent]
            ]
        ]
    }
}
