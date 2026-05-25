//
//  CosmosDiscoveryIntegrationTests.swift
//  VultisigAppTests
//
//  Pins the vault-integration contract for Terra / TerraClassic bank-denom
//  discovery. Sibling to `CosmosCoinFinderTests` (which pins the resolver
//  itself); this file covers the wiring inside `CoinService` — every
//  discovered denom auto-adds via `insertVisibleDiscoveredToken`
//  regardless of `isHidden`, with idempotency on repeat refresh.
//
//  The duplicate-insert hazard is the sRUJI / wallet-list-flicker pathology
//  fixed in PR #4342 — without per-refresh idempotency, every chain-detail
//  refresh would stack a fresh `Coin` row for each held bank denom.
//

@testable import VultisigApp
import XCTest

@MainActor
final class CosmosDiscoveryIntegrationTests: XCTestCase {

    private var token: TestContextToken?

    override func setUpWithError() throws {
        try super.setUpWithError()
        token = try TestStore.installInMemoryContainer()
    }

    override func tearDown() {
        TestStore.restore(token)
        token = nil
        super.tearDown()
    }

    // MARK: - Visible-discovery: refresh-preserves invariant

    func testVisibleDiscoveryNoOpsWhenCoinAlreadyExists() throws {
        // Refresh-preserves: a discovered visible denom whose `Coin` is
        // already on the vault must NOT be re-inserted on a second pass.
        // This is the sRUJI duplicate-insert regression — see
        // `Vault.coin(for:)` which dedupes by (chain, ticker, contract).
        let vault = TestStore.makeVault()
        let meta = CoinMeta(
            chain: .terra,
            ticker: "ASTRO-IBC",
            logo: "terra-astroport",
            decimals: 6,
            priceProviderId: "astroport-fi",
            contractAddress: "ibc/8D8A7F7253615E5F76CB6252A1E1BD921D5EDB7BBAAF8913FB1C77FF125D9995",
            isNativeToken: false
        )

        let preexisting = Coin(asset: meta, address: "terra1abc", hexPublicKey: "deadbeef")
        Storage.shared.insert([preexisting])
        vault.coins.append(preexisting)

        XCTAssertEqual(vault.coins.count, 1, "Sanity: vault starts with the pre-existing coin")

        CoinService.insertVisibleDiscoveredToken(meta: meta, into: vault)

        XCTAssertEqual(vault.coins.count, 1, "Discovery must NOT duplicate an existing coin row")
        XCTAssertTrue(vault.coins.contains(where: { $0.id == preexisting.id }))
    }

    func testVisibleDiscoverySkipsWhenUserHidThePreviousVersion() throws {
        // A user who removed a discovered token through Manage Tokens
        // sees it land in `hiddenTokens`. A subsequent discovery refresh
        // must NOT re-promote it back into `vault.coins` — that would
        // undo the user's intent.
        let vault = TestStore.makeVault()
        let meta = CoinMeta(
            chain: .terra,
            ticker: "ASTRO-IBC",
            logo: "terra-astroport",
            decimals: 6,
            priceProviderId: "astroport-fi",
            contractAddress: "ibc/8D8A7F7253615E5F76CB6252A1E1BD921D5EDB7BBAAF8913FB1C77FF125D9995",
            isNativeToken: false
        )

        let hiddenByUser = HiddenToken(
            chain: meta.chain,
            ticker: meta.ticker,
            contractAddress: meta.contractAddress
        )
        Storage.shared.insert([hiddenByUser])
        vault.hiddenTokens.append(hiddenByUser)

        CoinService.insertVisibleDiscoveredToken(meta: meta, into: vault)

        XCTAssertTrue(vault.coins.isEmpty, "User-hidden discovery must NOT auto-promote on next refresh")
        XCTAssertEqual(vault.hiddenTokens.count, 1)
    }

    // MARK: - Full routing layer: `applyCosmosDiscoveredTokens`

    func testApplyRoutesEveryDenomToVisibleInsertion() throws {
        // Every discovered denom — `isHidden` or not — routes to
        // `insertVisibleDiscoveredToken`. No `HiddenToken` branch.
        // Pre-seed both pre-existing visible coins so the dedupe check
        // makes the test independent of `CoinFactory.create` (which
        // requires real key material we can't conjure here).
        let vault = TestStore.makeVault()

        let ustcMeta = CoinMeta(
            chain: .terraClassic,
            ticker: "USTC",
            logo: "ustc",
            decimals: 6,
            priceProviderId: "terrausd",
            contractAddress: "uusd",
            isNativeToken: false
        )
        let preexistingUstc = Coin(asset: ustcMeta, address: "terra1classic", hexPublicKey: "deadbeef")
        Storage.shared.insert([preexistingUstc])
        vault.coins.append(preexistingUstc)

        // Pre-seed the formerly-hidden factory denom too so the routing
        // dedupes via `vault.coin(for:)` instead of attempting `addToChain`.
        let factoryMeta = CoinMeta(
            chain: .terraClassic,
            ticker: "xyz",
            logo: "",
            decimals: 6,
            priceProviderId: "",
            contractAddress: "factory/terra1minter/uxyz",
            isNativeToken: false
        )
        let preexistingFactory = Coin(asset: factoryMeta, address: "terra1classic", hexPublicKey: "deadbeef")
        Storage.shared.insert([preexistingFactory])
        vault.coins.append(preexistingFactory)

        let lunc = CoinMeta(
            chain: .terraClassic,
            ticker: "LUNC",
            logo: "lunc",
            decimals: 6,
            priceProviderId: "terra-luna",
            contractAddress: "",
            isNativeToken: true
        )
        let nativeCoin = Coin(asset: lunc, address: "terra1classic", hexPublicKey: "feedface")
        Storage.shared.insert([nativeCoin])
        vault.coins.append(nativeCoin)

        let discovered: [DiscoveredCosmosDenom] = [
            DiscoveredCosmosDenom(
                denom: "uusd",
                ticker: "USTC",
                decimals: 6,
                logo: "ustc",
                priceProviderId: "terrausd",
                isHidden: false
            ),
            DiscoveredCosmosDenom(
                denom: "factory/terra1minter/uxyz",
                ticker: "xyz",
                decimals: 6,
                logo: "",
                priceProviderId: "",
                isHidden: true
            )
        ]

        CoinService.applyCosmosDiscoveredTokens(discovered: discovered, nativeToken: nativeCoin, to: vault)

        // Both pre-existing coins survive — no duplicates from the
        // discovery routing. `isHidden` no longer routes to `hiddenTokens`.
        XCTAssertEqual(vault.coins.filter { $0.ticker == "USTC" }.count, 1)
        XCTAssertEqual(vault.coins.filter { $0.ticker == "xyz" }.count, 1)
        XCTAssertTrue(vault.hiddenTokens.isEmpty, "Discovery must NOT route any denom to hiddenTokens")

        // Second pass — idempotency on the full routing layer.
        CoinService.applyCosmosDiscoveredTokens(discovered: discovered, nativeToken: nativeCoin, to: vault)
        XCTAssertEqual(vault.coins.filter { $0.ticker == "USTC" }.count, 1)
        XCTAssertEqual(vault.coins.filter { $0.ticker == "xyz" }.count, 1)
        XCTAssertTrue(vault.hiddenTokens.isEmpty)
    }

    func testApplySkipsNativeTickerEvenWhenSurfacedByResolver() throws {
        // Defensive: if the resolver ever forgets to filter the native fee
        // denom, the routing layer must still skip a discovered token that
        // collides with the native ticker (mirrors the existing
        // `addDiscoveredTokens` skip for THORChain's `rune` denom).
        let vault = TestStore.makeVault()
        let lunc = CoinMeta(
            chain: .terraClassic,
            ticker: "LUNC",
            logo: "lunc",
            decimals: 6,
            priceProviderId: "terra-luna",
            contractAddress: "",
            isNativeToken: true
        )
        let nativeCoin = Coin(asset: lunc, address: "terra1classic", hexPublicKey: "feedface")
        Storage.shared.insert([nativeCoin])
        vault.coins.append(nativeCoin)

        let discovered: [DiscoveredCosmosDenom] = [
            DiscoveredCosmosDenom(
                denom: "uluna",
                ticker: "LUNC",
                decimals: 6,
                logo: "lunc",
                priceProviderId: "terra-luna",
                isHidden: false
            )
        ]

        CoinService.applyCosmosDiscoveredTokens(discovered: discovered, nativeToken: nativeCoin, to: vault)

        XCTAssertEqual(vault.coins.count, 1, "Native-ticker collision must short-circuit")
        XCTAssertTrue(vault.hiddenTokens.isEmpty)
    }
}
