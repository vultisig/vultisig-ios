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

    func testDecimalsFromMetaSymbolPrevailsOverDisplay() {
        // SDK coalesce: `meta.symbol || meta.display` picks the unit key.
        // When symbol is populated and matches a `denom_units` entry, that
        // entry's exponent wins even if `display` would have resolved to a
        // different one. Pins the Terra Classic USTC scenario from the
        // SDK port note.
        let meta = CosmosDenomMetadata(
            base: "uusd",
            symbol: "USTC",
            display: "uusd",
            denomUnits: [
                CosmosDenomUnit(denom: "uusd", exponent: 0),
                CosmosDenomUnit(denom: "USTC", exponent: 6)
            ]
        )
        XCTAssertEqual(CosmosTokenMetadataResolver.decimalsFromMeta(meta), 6)
    }

    func testDecimalsFromMetaFallsBackToDisplayWhenSymbolMissing() {
        // No symbol → coalesce resolves to `display`. Standard Cosmos shape
        // for chains that don't populate symbol on every denom.
        let meta = CosmosDenomMetadata(
            base: "uluna",
            symbol: nil,
            display: "uusd",
            denomUnits: [
                CosmosDenomUnit(denom: "uusd", exponent: 6)
            ]
        )
        XCTAssertEqual(CosmosTokenMetadataResolver.decimalsFromMeta(meta), 6)
    }

    func testDecimalsFromMetaHandlesEighteenDecimalIbcDenom() {
        // Scenario: ETH-backed IBC denoms on Terra carry exponent 18 in
        // metadata. The wallet must NOT default to 6 just because LUNA is.
        // Symbol matches the high-exponent unit per SDK coalesce.
        let meta = CosmosDenomMetadata(
            base: "ibc/eth-weth",
            symbol: "weth",
            display: "weth",
            denomUnits: [
                CosmosDenomUnit(denom: "ibc/eth-weth", exponent: 0),
                CosmosDenomUnit(denom: "weth", exponent: 18)
            ]
        )
        XCTAssertEqual(CosmosTokenMetadataResolver.decimalsFromMeta(meta), 18)
    }

    func testDecimalsFromMetaReturnsNilWhenDisplayMissing() {
        // SDK guard: `if (!meta.denom_units || !meta.display) return null`.
        // Even if symbol + units are present, missing display short-circuits.
        let meta = CosmosDenomMetadata(
            base: "uluna",
            symbol: "LUNA",
            display: nil,
            denomUnits: [CosmosDenomUnit(denom: "LUNA", exponent: 6)]
        )
        XCTAssertNil(CosmosTokenMetadataResolver.decimalsFromMeta(meta))
    }

    func testDecimalsFromMetaReturnsNilWhenDenomUnitsMissing() {
        // SDK guard: missing `denom_units` returns null.
        let meta = CosmosDenomMetadata(
            base: "uluna",
            symbol: "LUNA",
            display: "luna",
            denomUnits: nil
        )
        XCTAssertNil(CosmosTokenMetadataResolver.decimalsFromMeta(meta))
    }

    func testDecimalsFromMetaReturnsNilWhenNoUnitMatchesLookupKey() {
        // Coalesce key (symbol||display) doesn't match any `denom_units`
        // entry → `find` returns undefined → exponent ?? null in SDK.
        let meta = CosmosDenomMetadata(
            base: "uluna",
            symbol: nil,
            display: "luna",
            denomUnits: [CosmosDenomUnit(denom: "atom", exponent: 6)]
        )
        XCTAssertNil(CosmosTokenMetadataResolver.decimalsFromMeta(meta))
    }

    func testDecimalsFromMetaWithDisplayPathAndNoSymbol() {
        // Phoenix-1 LUNA shape: no symbol, display = "luna" matches the
        // exponent-6 unit. SDK coalesce resolves to `display`.
        let meta = CosmosDenomMetadata(
            base: "uluna",
            symbol: nil,
            display: "luna",
            denomUnits: [
                CosmosDenomUnit(denom: "uluna", exponent: 0),
                CosmosDenomUnit(denom: "luna", exponent: 6)
            ]
        )
        XCTAssertEqual(CosmosTokenMetadataResolver.decimalsFromMeta(meta), 6)
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

    func testDeriveTickerIbcDenomTruncatesToShortHash() {
        // Unresolved voucher -> IBC-<6hex uppercase>, never the raw 64-char
        // hash. Mirrors Android `String.toCosmosTicker`. Uses a lowercase
        // hash so the uppercasing is actually exercised.
        let ticker = CosmosTokenMetadataResolver.deriveTicker(
            denom: "ibc/0bb9d8513e8e8e9ae6a9d211d9136e6da42288dde6cfaa453a150a4566054dc5",
            meta: nil
        )
        XCTAssertEqual(ticker, "IBC-0BB9D8")
    }

    func testDeriveTickerIbcDenomWithEmptyHashFallsThrough() {
        // A malformed `ibc/` with no hash must not produce a bare `IBC-`
        // label — it falls through to the raw-denom return.
        let ticker = CosmosTokenMetadataResolver.deriveTicker(denom: "ibc/", meta: nil)
        XCTAssertEqual(ticker, "ibc/")
    }

    // MARK: - IBC ticker derivation (pure)

    func testIbcTickerStripsMicroPrefixAndUppercases() {
        // Standard micro-denoms: strip the leading `u`, uppercase.
        XCTAssertEqual(CosmosTokenMetadataResolver.ibcTicker(baseDenom: "uusdc"), "USDC")
        XCTAssertEqual(CosmosTokenMetadataResolver.ibcTicker(baseDenom: "uatom"), "ATOM")
    }

    func testIbcTickerStripsAttoPrefix() {
        // `a` (atto) is a valid micro-unit prefix on EVM-on-Cosmos chains.
        XCTAssertEqual(CosmosTokenMetadataResolver.ibcTicker(baseDenom: "aevmos"), "EVMOS")
    }

    func testIbcTickerLeavesNonPrefixedDenomUppercased() {
        // No leading u/a micro prefix -> just uppercase, no strip.
        XCTAssertEqual(CosmosTokenMetadataResolver.ibcTicker(baseDenom: "gravity0x123"), "GRAVITY0X123")
    }

    func testIbcTickerLeavesSingleCharDenomUntouched() {
        // Guard: length must exceed 1 before stripping, so a lone `u`/`a`
        // survives (just uppercased).
        XCTAssertEqual(CosmosTokenMetadataResolver.ibcTicker(baseDenom: "u"), "U")
    }

    func testIbcTickerDoesNotStripWhenSecondCharIsNotLetter() {
        // The prefix is stripped only when the second character is a letter
        // (Android `stripDenomUnitPrefix` guard), so `u123` / `a0x` keep their
        // leading char — they are not micro-denominated units.
        XCTAssertEqual(CosmosTokenMetadataResolver.ibcTicker(baseDenom: "u123"), "U123")
        XCTAssertEqual(CosmosTokenMetadataResolver.ibcTicker(baseDenom: "a0x"), "A0X")
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
        // Stub uses symbol == unitDenom to match the SDK's
        // `symbol || display` coalesce — most Cosmos LCDs publish symbol
        // as the canonical unit key for the human-readable exponent row.
        stub.denomMetadataPayloads[ibcWeth] = ScriptedHTTPClient.MetaPayload(
            symbol: "weth",
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
        XCTAssertEqual(weth.ticker, "weth", "Ticker mirrors the metadata symbol verbatim")
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
        // SDK coalesce: symbol == unitDenom so the lookup hits the
        // human-readable unit row.
        stub.denomMetadataPayloads[baseDenom] = ScriptedHTTPClient.MetaPayload(
            symbol: "atom",
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
        XCTAssertEqual(atom.ticker, "atom")
        XCTAssertEqual(atom.decimals, 6)
        XCTAssertTrue(atom.isHidden, "IBC trace path always sets isHidden = true")
    }

    // MARK: - Terra Classic modern IBC resolution (#4761)

    func testTerraClassicReportedIbcTokenResolvesToUsdcViaTokensStore() async throws {
        // The token in the bug report is Axelar USDC. A curated TokensStore
        // entry keyed by the full ibc/<hash> contract resolves it at Tier 0
        // -> symbol + logo + fiat, with no LCD metadata round-trip.
        let reportedDenom = "ibc/0BB9D8513E8E8E9AE6A9D211D9136E6DA42288DDE6CFAA453A150A4566054DC5"
        let stub = ScriptedHTTPClient()
        stub.balances = [
            ("uluna", "1000"),
            (reportedDenom, "5000000")
        ]

        let finder = CosmosCoinFinder(
            httpClient: stub,
            metadataResolver: makeIsolatedResolver(client: stub)
        )
        let result = try await finder.discoverBankDenoms(
            chain: .terraClassic,
            address: "terra1classic"
        )

        XCTAssertEqual(result.count, 1)
        let usdc = try XCTUnwrap(result.first)
        XCTAssertEqual(usdc.denom, reportedDenom)
        XCTAssertEqual(usdc.ticker, "USDC")
        XCTAssertEqual(usdc.decimals, 6)
        XCTAssertEqual(usdc.priceProviderId, "usd-coin")
        XCTAssertFalse(usdc.logo.isEmpty, "Curated entry must supply the USDC logo")
        XCTAssertFalse(usdc.isHidden)
        XCTAssertEqual(
            stub.ibcDenomCallCount,
            0,
            "Curated Tier 0 must short-circuit before the /denoms endpoint"
        )
        XCTAssertEqual(stub.ibcTraceCallCount, 0)
        XCTAssertEqual(
            stub.totalCallCount,
            1,
            "Only the balance fetch — curated Tier 0 must not hit any metadata/denoms LCD call"
        )
    }

    func testTerraClassicIbcDenomResolvesViaModernDenomsEndpoint() async throws {
        // A non-curated ibc voucher on Terra Classic resolves through the
        // modern /denoms endpoint: base `uusdc` -> ticker `USDC`. Terra
        // Classic implements /denoms even though it rejects the deprecated
        // denom_traces path, so the trace endpoint must NOT be hit. Decimals
        // fall back to the chain fee-coin (6) because the base denom has no
        // bank metadata, and the derived USDC ticker backfills the curated
        // logo / priceProviderId.
        let ibcHash = "AXLUSDCUNKNOWNHASH"
        let ibcDenom = "ibc/\(ibcHash)"
        let stub = ScriptedHTTPClient()
        stub.balances = [
            ("uluna", "1000"),
            (ibcDenom, "5000000")
        ]
        stub.ibcDenomPayloads[ibcHash] = "uusdc"

        let finder = CosmosCoinFinder(
            httpClient: stub,
            metadataResolver: makeIsolatedResolver(client: stub)
        )
        let result = try await finder.discoverBankDenoms(
            chain: .terraClassic,
            address: "terra1classic"
        )

        XCTAssertEqual(result.count, 1)
        let usdc = try XCTUnwrap(result.first)
        XCTAssertEqual(usdc.denom, ibcDenom, "Discovered denom must be the on-chain ibc/<hash> id")
        XCTAssertEqual(usdc.ticker, "USDC")
        XCTAssertEqual(usdc.decimals, 6, "No base-denom metadata -> chain fee-coin decimals")
        XCTAssertTrue(usdc.isHidden, "Discovered IBC voucher stays hidden per SDK semantics")
        XCTAssertFalse(usdc.logo.isEmpty, "Derived USDC ticker backfills the curated logo")
        XCTAssertEqual(stub.ibcDenomCallCount, 1, "Terra Classic must hit the modern /denoms endpoint")
        XCTAssertEqual(
            stub.ibcTraceCallCount,
            0,
            "Terra Classic must NOT hit the deprecated denom_traces endpoint"
        )
    }

    func testTerraClassicIbcDenomFallsBackToTruncatedTickerWhenDenomsNotFound() async throws {
        // When /denoms returns NotFound for an unknown voucher, the finder
        // degrades to a short IBC-<6hex> label (Android parity) instead of
        // the raw 64-char hash, and marks it hidden — never dropped.
        let ibcHash = "0BB9D8FFEEDDCCBBAA"
        let ibcDenom = "ibc/\(ibcHash)"
        let stub = ScriptedHTTPClient()
        stub.balances = [
            ("uluna", "1000"),
            (ibcDenom, "999")
        ]
        // No ibcDenomPayloads entry -> the stub answers 404 (gRPC NOT_FOUND).

        let finder = CosmosCoinFinder(
            httpClient: stub,
            metadataResolver: makeIsolatedResolver(client: stub)
        )
        let result = try await finder.discoverBankDenoms(
            chain: .terraClassic,
            address: "terra1classic"
        )

        XCTAssertEqual(result.count, 1, "Unresolved vouchers are surfaced hidden, not dropped")
        let hidden = try XCTUnwrap(result.first)
        XCTAssertEqual(hidden.denom, ibcDenom)
        XCTAssertEqual(
            hidden.ticker,
            "IBC-0BB9D8",
            "Fallback truncates to IBC-<6hex uppercase>, never the raw hash"
        )
        XCTAssertNotEqual(hidden.ticker, ibcDenom, "The raw ibc/<hash> denom must never become the ticker")
        XCTAssertEqual(hidden.decimals, 6, "Hidden tier uses chain fee-coin decimals")
        XCTAssertTrue(hidden.isHidden)
        XCTAssertEqual(stub.ibcDenomCallCount, 1, "Must attempt the modern /denoms endpoint")
        XCTAssertEqual(
            stub.ibcTraceCallCount,
            0,
            "Terra Classic must NOT hit the deprecated denom_traces endpoint"
        )
    }

    func testTerraPhoenix1IbcDenomStillUsesTraceEndpoint() async throws {
        // Phoenix-1 LCDs implement the denom_traces endpoint, so the
        // recursion is still wired up there — no regression vs. the
        // pre-Classic-fix behaviour.
        let ibcHash = "PHOENIXHASH"
        let ibcDenom = "ibc/\(ibcHash)"
        let baseDenom = "uatom"
        let stub = ScriptedHTTPClient()
        stub.balances = [(ibcDenom, "1")]
        stub.ibcTracePayloads[ibcHash] = ScriptedHTTPClient.TracePayload(
            path: "transfer/channel-0",
            baseDenom: baseDenom
        )
        stub.denomMetadataPayloads[baseDenom] = ScriptedHTTPClient.MetaPayload(
            symbol: "atom",
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
        XCTAssertEqual(stub.ibcTraceCallCount, 1, "Phoenix-1 must hit the trace endpoint")
        let atom = try XCTUnwrap(result.first)
        XCTAssertEqual(atom.ticker, "atom")
        XCTAssertTrue(atom.isHidden, "IBC trace path always marks the discovered denom hidden")
    }

    func testIbcTraceCacheCoalescesConcurrentLookupsOnPhoenix() async {
        // Cache contract on the IBC trace path: two concurrent lookups for
        // the same denom share one HTTP round-trip, matching the metadata
        // resolver's Task-cell coalescing.
        let stub = ScriptedHTTPClient()
        let ibcHash = "DEADBEEF"
        let ibcDenom = "ibc/\(ibcHash)"
        stub.ibcTracePayloads[ibcHash] = ScriptedHTTPClient.TracePayload(
            path: "transfer/channel-0",
            baseDenom: "uatom"
        )
        let resolver = makeIsolatedResolver(client: stub)

        async let first = resolver.ibcDenomTrace(chain: .terra, denom: ibcDenom)
        async let second = resolver.ibcDenomTrace(chain: .terra, denom: ibcDenom)
        let (a, b) = await (first, second)

        XCTAssertEqual(a?.baseDenom, "uatom")
        XCTAssertEqual(b?.baseDenom, "uatom")
        XCTAssertEqual(
            stub.ibcTraceCallCount,
            1,
            "Concurrent in-flight trace lookups must share one round-trip"
        )
    }

    func testIbcTraceCacheEvictsEntryOnNetworkError() async {
        // Transient LCD failure on the trace path must NOT poison the
        // cache for 24h. After a failed call, the next call retries.
        let stub = ScriptedHTTPClient()
        let ibcHash = "DEADBEEF"
        let ibcDenom = "ibc/\(ibcHash)"
        stub.shouldFailAllRequests = true
        let resolver = makeIsolatedResolver(client: stub)

        let first = await resolver.ibcDenomTrace(chain: .terra, denom: ibcDenom)
        XCTAssertNil(first, "First call returns nil because the LCD is failing")

        // LCD comes back: cache must have been evicted so the retry hits.
        stub.shouldFailAllRequests = false
        stub.ibcTracePayloads[ibcHash] = ScriptedHTTPClient.TracePayload(
            path: "transfer/channel-0",
            baseDenom: "uatom"
        )
        let second = await resolver.ibcDenomTrace(chain: .terra, denom: ibcDenom)
        XCTAssertEqual(second?.baseDenom, "uatom", "Cache eviction must let the retry succeed")
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

    // MARK: - Modern IBC denom resolution cache

    func testIbcDenomShortCircuitsForNonIbcDenom() async {
        // Same prefix guard as ibcDenomTrace: `uluna` must return nil WITHOUT
        // a /denoms round-trip.
        let stub = ScriptedHTTPClient()
        let resolver = makeIsolatedResolver(client: stub)

        let result = await resolver.ibcDenom(chain: .terraClassic, denom: "uluna")
        XCTAssertNil(result)
        XCTAssertEqual(stub.ibcDenomCallCount, 0, "Non-IBC denoms must not trigger a /denoms lookup")
    }

    func testIbcDenomCacheCoalescesConcurrentLookups() async {
        // Two concurrent lookups for the same voucher share one /denoms
        // round-trip — same Task-cell coalescing as the metadata/trace caches.
        let stub = ScriptedHTTPClient()
        let ibcHash = "DEADBEEF"
        let ibcDenom = "ibc/\(ibcHash)"
        stub.ibcDenomPayloads[ibcHash] = "uusdc"
        let resolver = makeIsolatedResolver(client: stub)

        async let first = resolver.ibcDenom(chain: .terraClassic, denom: ibcDenom)
        async let second = resolver.ibcDenom(chain: .terraClassic, denom: ibcDenom)
        let (a, b) = await (first, second)

        XCTAssertEqual(a, "uusdc")
        XCTAssertEqual(b, "uusdc")
        XCTAssertEqual(
            stub.ibcDenomCallCount,
            1,
            "Concurrent in-flight /denoms lookups must share one round-trip"
        )
    }

    func testIbcDenomReturnsNilForUnknownVoucher() async {
        // The modern endpoint answers 404 (gRPC NOT_FOUND) for an unknown
        // voucher; the resolver must surface that as nil, not throw.
        let stub = ScriptedHTTPClient()
        let ibcDenom = "ibc/UNKNOWNVOUCHER"
        let resolver = makeIsolatedResolver(client: stub)

        let result = await resolver.ibcDenom(chain: .terraClassic, denom: ibcDenom)
        XCTAssertNil(result)
        XCTAssertEqual(stub.ibcDenomCallCount, 1)
    }

    // MARK: - CosmosIbcDenom decoding

    func testCosmosIbcDenomDecodesResolvedShape() throws {
        let json = Data(#"{"denom":{"base":"uusdc","trace":[{"port_id":"transfer","channel_id":"channel-113"}]}}"#.utf8)
        let decoded = try JSONDecoder().decode(CosmosIbcDenom.self, from: json)
        XCTAssertEqual(decoded.denom?.base, "uusdc")
        XCTAssertEqual(decoded.denom?.trace?.first?.channelId, "channel-113")
        XCTAssertEqual(decoded.denom?.trace?.first?.portId, "transfer")
    }

    func testCosmosIbcDenomDecodesNotFoundShapeToNilBase() throws {
        // gRPC NOT_FOUND body must decode to a nil denom (unresolved) rather
        // than throwing a decode error.
        let json = Data(#"{"code":5,"message":"denomination trace not found"}"#.utf8)
        let decoded = try JSONDecoder().decode(CosmosIbcDenom.self, from: json)
        XCTAssertNil(decoded.denom)
        XCTAssertNil(decoded.denom?.base)
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
    /// Modern `/denoms/{hash}` responses: hash -> resolved base denom. A hash
    /// with no entry answers HTTP 404 (gRPC NOT_FOUND), matching the modern
    /// endpoint's reply for an unknown voucher.
    var ibcDenomPayloads: [String: String] = [:]
    var shouldFailAllRequests = false

    private let queue = DispatchQueue(label: "ScriptedHTTPClient.queue")
    private var _denomMetadataCalls: [String: Int] = [:]
    private var _ibcTraceCalls = 0
    private var _ibcDenomCalls = 0
    private var _totalCalls = 0

    func denomMetadataCallCount(for denom: String) -> Int {
        queue.sync { _denomMetadataCalls[denom] ?? 0 }
    }

    var ibcTraceCallCount: Int {
        queue.sync { _ibcTraceCalls }
    }

    var ibcDenomCallCount: Int {
        queue.sync { _ibcDenomCalls }
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

        case .ibcDenom(let hash):
            queue.sync { _ibcDenomCalls += 1 }
            guard let baseDenom = ibcDenomPayloads[hash] else {
                // Unknown voucher: the modern endpoint answers gRPC NOT_FOUND
                // (HTTP 404). The resolver must treat this as unresolved (nil).
                throw HTTPError.statusCode(404, nil)
            }
            let envelope: [String: Any] = [
                "denom": [
                    "base": baseDenom,
                    "trace": [["port_id": "transfer", "channel_id": "channel-113"]]
                ]
            ]
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
