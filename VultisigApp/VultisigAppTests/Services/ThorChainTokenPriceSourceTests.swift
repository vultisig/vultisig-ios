//
//  ThorChainTokenPriceSourceTests.swift
//  VultisigAppTests
//
//  THORChain *derived* assets have no L1 pool, so the pool lookup that prices
//  every other THORChain token reports 0 for them ("asset: THOR.BRUNE is a
//  derived asset"). These tests pin the fallback that reads the CoinGecko feed
//  the curated `TokensStore` entry declares — bRUNE names RUNE's feed, so it
//  prices at RUNE parity — and pin that every asset which does have a pool
//  (TCY, RUJI and their staking receipts) still prices from it.
//
//  Every case here deliberately drives the source directly, which is the shape
//  of the only coins that reach it in production: `RateProvider.cryptoId(for:)`
//  routes a THORChain coin that carries a `priceProviderId` to the provider-id
//  fetch instead, so a curated coin never asks for a pool price. What lands here
//  is a coin persisted *without* one — auto-discovered before its curated entry
//  existed and never re-synced. `testRoutingSendsOnlyAStaleCoinDownThisPath`
//  pins that precondition against `RateProvider` itself.
//

@testable import VultisigApp
import XCTest

final class ThorChainTokenPriceSourceTests: XCTestCase {

    private static let runeUSD = 1.75

    // MARK: - The routing precondition

    func testRoutingSendsOnlyAStaleCoinDownThisPath() {
        // Curated bRUNE declares RUNE's feed, so it never reaches this source.
        guard case .priceProvider(let id) = RateProvider.cryptoId(for: TokensStore.brune) else {
            return XCTFail("Curated bRUNE should price from its declared feed, not its contract")
        }
        XCTAssertEqual(id, TokensStore.rune.priceProviderId)

        // A bRUNE persisted before that entry existed carries no feed, so its
        // rate is keyed by the contract denom and priced by this source.
        guard case .contract(let contract) = RateProvider.cryptoId(for: staleBRune) else {
            return XCTFail("A bRUNE without a declared feed should price from its contract")
        }
        XCTAssertEqual(contract, TokensStore.brune.contractAddress)
    }

    // MARK: - bRUNE: RUNE parity

    func testBRunePricesAtRuneParityWhenPoolReportsNoPrice() async throws {
        let feed = FeedStore(cached: Self.runeUSD)
        let source = makeSource(pool: PoolPriceRecorder(price: 0), feed: feed)

        let rates = try await source.prices(contracts: [TokensStore.brune.contractAddress], coins: [])

        XCTAssertEqual(rates, [
            Rate(fiat: "usd", crypto: TokensStore.brune.contractAddress, value: Self.runeUSD)
        ])
        // Parity comes from the feed the curated entry declares, which is RUNE's.
        XCTAssertEqual(feed.queriedProviderIds, [TokensStore.rune.priceProviderId])
        XCTAssertEqual(feed.fetchedProviderIds, [])
    }

    func testBRunePoolLookupTargetsTheDerivedAssetNameBeforeFallingBack() async throws {
        let poolRecorder = PoolPriceRecorder(price: 0)
        let source = makeSource(pool: poolRecorder, feed: FeedStore(cached: Self.runeUSD))

        _ = try await source.prices(contracts: [TokensStore.brune.contractAddress], coins: [])

        let assetNames = await poolRecorder.assetNames
        XCTAssertEqual(assetNames, ["THOR.BRUNE"])
    }

    func testBRuneFetchesTheRuneFeedWhenItIsNotCachedYet() async throws {
        // A single-coin refresh carries no coin that names RUNE's feed, so on a
        // cold cache the feed has to be fetched here or bRUNE stays at $0.
        let feed = FeedStore(cached: nil, afterFetch: Self.runeUSD)
        let source = makeSource(pool: PoolPriceRecorder(price: 0), feed: feed)

        let rates = try await source.prices(contracts: [TokensStore.brune.contractAddress], coins: [])

        XCTAssertEqual(rates, [
            Rate(fiat: "usd", crypto: TokensStore.brune.contractAddress, value: Self.runeUSD)
        ])
        XCTAssertEqual(feed.fetchedProviderIds, [TokensStore.rune.priceProviderId])
    }

    func testBRuneReportsZeroWhenTheRuneFeedCannotBeResolved() async throws {
        let feed = FeedStore(cached: nil)
        let source = makeSource(pool: PoolPriceRecorder(price: 0), feed: feed)

        let rates = try await source.prices(contracts: [TokensStore.brune.contractAddress], coins: [])

        XCTAssertEqual(rates, [
            Rate(fiat: "usd", crypto: TokensStore.brune.contractAddress, value: 0)
        ])
        XCTAssertEqual(feed.fetchedProviderIds, [TokensStore.rune.priceProviderId])
    }

    func testAnUnresolvableFeedIsFetchedOncePerBatchNotOncePerContract() async throws {
        // A stale TCY and sTCY both name the `tcy` feed; one failed fetch per
        // refresh is enough, and a later refresh gets to retry.
        let feed = FeedStore(cached: nil)
        let source = makeSource(pool: PoolPriceRecorder(price: 0), feed: feed)

        let rates = try await source.prices(
            contracts: [TokensStore.tcy.contractAddress, TokensStore.stcy.contractAddress],
            coins: []
        )

        XCTAssertEqual(rates, [
            Rate(fiat: "usd", crypto: TokensStore.tcy.contractAddress, value: 0),
            Rate(fiat: "usd", crypto: TokensStore.stcy.contractAddress, value: 0)
        ])
        XCTAssertEqual(feed.fetchedProviderIds, [TokensStore.tcy.priceProviderId])
    }

    // MARK: - ybRUNE keeps the yield path

    func testYbRuneStillResolvesThroughTheYieldPath() async throws {
        let poolRecorder = PoolPriceRecorder(price: 9.99)
        let yieldRecorder = YieldPriceRecorder(price: 2.5)
        let feed = FeedStore(cached: Self.runeUSD)
        let source = makeSource(pool: poolRecorder, yield: yieldRecorder, feed: feed)

        let rates = try await source.prices(contracts: [TokensStore.ybrune.contractAddress], coins: [])

        XCTAssertEqual(rates, [
            Rate(fiat: "usd", crypto: TokensStore.ybrune.contractAddress, value: 2.5)
        ])
        let yieldContracts = await yieldRecorder.contracts
        XCTAssertEqual(yieldContracts, [TokensStore.ybrune.contractAddress])
        // A naive `x/` strip would turn `x/staking-x/brune` into the same
        // nonexistent THOR.BRUNE pool, so the yield branch must win outright.
        let poolAssetNames = await poolRecorder.assetNames
        XCTAssertTrue(poolAssetNames.isEmpty)
        XCTAssertEqual(feed.queriedProviderIds, [])
    }

    // MARK: - Regression guards: assets that do have a pool

    func testTcyKeepsItsPoolPriceAndIgnoresTheDeclaredFeed() async throws {
        // TCY has an Available THOR.TCY pool and is deliberately priced from it.
        let feed = FeedStore(cached: 999)
        let source = makeSource(pool: PoolPriceRecorder(price: 3.0), feed: feed)

        let rates = try await source.prices(contracts: [TokensStore.tcy.contractAddress], coins: [])

        XCTAssertEqual(rates, [
            Rate(fiat: "usd", crypto: TokensStore.tcy.contractAddress, value: 3.0)
        ])
        XCTAssertEqual(feed.queriedProviderIds, [])
    }

    func testRujiAndStakedRujiKeepTheirPoolPrice() async throws {
        let poolRecorder = PoolPriceRecorder(price: 1.1)
        let feed = FeedStore(cached: 999)
        let source = makeSource(pool: poolRecorder, feed: feed)

        let rates = try await source.prices(
            contracts: [TokensStore.ruji.contractAddress, TokensStore.sruji.contractAddress],
            coins: []
        )

        XCTAssertEqual(rates, [
            Rate(fiat: "usd", crypto: TokensStore.ruji.contractAddress, value: 1.1),
            Rate(fiat: "usd", crypto: TokensStore.sruji.contractAddress, value: 1.1)
        ])
        let assetNames = await poolRecorder.assetNames
        XCTAssertEqual(assetNames, ["THOR.RUJI", "THOR.RUJI"])
        XCTAssertEqual(feed.queriedProviderIds, [])
    }

    func testAssetWithNeitherPoolNorDeclaredFeedStillReportsZero() async throws {
        // LQDY has no pool and no `priceProviderId`; it reported $0 before and must
        // keep doing so rather than silently dropping out of the rate cache.
        let feed = FeedStore(cached: 999)
        let source = makeSource(pool: PoolPriceRecorder(price: 0), feed: feed)

        let rates = try await source.prices(contracts: ["thor.lqdy"], coins: [])

        XCTAssertEqual(rates, [Rate(fiat: "usd", crypto: "thor.lqdy", value: 0)])
        XCTAssertEqual(feed.queriedProviderIds, [])
    }

    // MARK: - Pool asset name mapping

    func testPoolAssetNameStripsXAndStakingPrefixes() {
        let name = ThorChainTokenPriceSource.poolAssetName
        XCTAssertEqual(name(TokensStore.brune.contractAddress), "THOR.BRUNE")
        XCTAssertEqual(name(TokensStore.ruji.contractAddress), "THOR.RUJI")
        XCTAssertEqual(name(TokensStore.sruji.contractAddress), "THOR.RUJI")
        XCTAssertEqual(name(TokensStore.stcy.contractAddress), "THOR.TCY")
        XCTAssertEqual(name(TokensStore.tcy.contractAddress), "THOR.TCY")
        XCTAssertEqual(name("thor.lvn"), "THOR.LVN")
    }

    // MARK: - Helpers

    /// bRUNE as a vault that auto-discovered it before the curated entry existed
    /// persisted it: the real denom, but no declared price feed.
    private var staleBRune: CoinMeta {
        CoinMeta(
            chain: .thorChain,
            ticker: "BRUNE",
            logo: .empty,
            decimals: 8,
            priceProviderId: .empty,
            contractAddress: TokensStore.brune.contractAddress,
            isNativeToken: false
        )
    }

    private func makeSource(
        pool: PoolPriceRecorder,
        yield: YieldPriceRecorder = YieldPriceRecorder(price: nil),
        feed: FeedStore
    ) -> ThorChainTokenPriceSource {
        ThorChainTokenPriceSource(
            chain: .thorChain,
            yieldPrice: { _, contract in await yield.price(contract: contract) },
            poolPrice: { _, assetName in await pool.price(assetName: assetName) },
            providerRate: { coin in feed.cachedRate(providerId: coin.priceProviderId) },
            fetchProviderFeed: { providerId in feed.fetch(providerId: providerId) }
        )
    }
}

/// Stands in for the cached CoinGecko rates a token's declared feed resolves to,
/// recording which feeds were read and which were fetched. Not thread-safe by
/// design — the source reads it serially from one task.
private final class FeedStore {
    private(set) var queriedProviderIds: [String] = []
    private(set) var fetchedProviderIds: [String] = []
    private var rate: Double?
    private let rateAfterFetch: Double?

    init(cached: Double?, afterFetch: Double? = nil) {
        self.rate = cached
        self.rateAfterFetch = afterFetch
    }

    func cachedRate(providerId: String) -> Double? {
        queriedProviderIds.append(providerId)
        return rate
    }

    func fetch(providerId: String) {
        fetchedProviderIds.append(providerId)
        if let rateAfterFetch {
            rate = rateAfterFetch
        }
    }
}

private actor PoolPriceRecorder {
    private(set) var assetNames: [String] = []
    private let priceValue: Double

    init(price: Double) {
        self.priceValue = price
    }

    func price(assetName: String) -> Double {
        assetNames.append(assetName)
        return priceValue
    }
}

private actor YieldPriceRecorder {
    private(set) var contracts: [String] = []
    private let priceValue: Double?

    init(price: Double?) {
        self.priceValue = price
    }

    func price(contract: String) -> Double? {
        contracts.append(contract)
        return priceValue
    }
}
