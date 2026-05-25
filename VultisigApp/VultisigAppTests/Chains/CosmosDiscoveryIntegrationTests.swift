//
//  CosmosDiscoveryIntegrationTests.swift
//  VultisigAppTests
//
//  Pins the vault-integration contract for Terra / TerraClassic bank-denom
//  discovery. Sibling to `CosmosCoinFinderTests` (which pins the resolver
//  itself); this file covers the wiring inside `CoinService` — visible
//  denoms land in `Vault.coins`, `isHidden` denoms land in `Vault.hiddenTokens`,
//  and re-running discovery on the same address is a no-op rather than a
//  duplicate-insert.
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

    // MARK: - Hidden-discovery: `isHidden` → `HiddenToken` shim

    func testHiddenDiscoveryInsertsHiddenTokenAndNotVisibleCoin() throws {
        // `isHidden = true` denoms (factory tokens without metadata, IBC
        // assets whose trace recursion failed) must land in `hiddenTokens`
        // — reachable through Manage Tokens — and NOT in `vault.coins`.
        let vault = TestStore.makeVault()
        let opaqueFactory = CoinMeta(
            chain: .terra,
            ticker: "xyz",
            logo: "",
            decimals: 6,
            priceProviderId: "",
            contractAddress: "factory/terra1minter/uxyz",
            isNativeToken: false
        )

        CoinService.insertHiddenDiscoveredToken(meta: opaqueFactory, into: vault)

        XCTAssertEqual(vault.hiddenTokens.count, 1)
        XCTAssertTrue(vault.coins.isEmpty, "isHidden discovery must not pollute Vault.coins")
        let hidden = try XCTUnwrap(vault.hiddenTokens.first)
        XCTAssertEqual(hidden.chain, Chain.terra.rawValue)
        XCTAssertEqual(hidden.ticker, "xyz")
        XCTAssertEqual(hidden.contractAddress, "factory/terra1minter/uxyz")
    }

    func testHiddenDiscoveryIsIdempotent() throws {
        // Discovery runs per chain-detail refresh; refreshes fan out 2-6×
        // post-swap. Inserting the same `isHidden` denom twice must yield
        // ONE `HiddenToken` row, not two — same regression class as the
        // sRUJI fix on the visible path.
        let vault = TestStore.makeVault()
        let opaqueFactory = CoinMeta(
            chain: .terra,
            ticker: "xyz",
            logo: "",
            decimals: 6,
            priceProviderId: "",
            contractAddress: "factory/terra1minter/uxyz",
            isNativeToken: false
        )

        CoinService.insertHiddenDiscoveredToken(meta: opaqueFactory, into: vault)
        CoinService.insertHiddenDiscoveredToken(meta: opaqueFactory, into: vault)

        XCTAssertEqual(vault.hiddenTokens.count, 1, "Second discovery pass must NOT duplicate the HiddenToken row")
    }

    func testHiddenDiscoveryNoOpsWhenCoinAlreadyVisible() throws {
        // If the user manually added a denom that discovery later flags as
        // `isHidden`, the discovery must NOT shadow it with a `HiddenToken`
        // — the user's visible coin wins.
        let vault = TestStore.makeVault()
        let meta = CoinMeta(
            chain: .terra,
            ticker: "TPT",
            logo: "terra-poker-token",
            decimals: 6,
            priceProviderId: "tpt",
            contractAddress: "terra13j2k5rfkg0qhk58vz63cze0uze4hwswlrfnm0fa4rnyggjyfrcnqcrs5z2",
            isNativeToken: false
        )
        let userAdded = Coin(asset: meta, address: "terra1abc", hexPublicKey: "deadbeef")
        Storage.shared.insert([userAdded])
        vault.coins.append(userAdded)

        CoinService.insertHiddenDiscoveredToken(meta: meta, into: vault)

        XCTAssertEqual(vault.coins.count, 1)
        XCTAssertTrue(vault.hiddenTokens.isEmpty, "Existing visible coin must NOT be shadowed by a HiddenToken row")
    }

    // MARK: - Full routing layer: `applyCosmosDiscoveredTokens`

    func testApplyRoutesVisibleAndHiddenInOnePass() throws {
        // Drives the routing seam end-to-end without an actor or LCD round
        // trip. A pre-built `[DiscoveredCosmosDenom]` carrying one visible
        // (TokensStore-curated USTC) and one hidden (factory denom) entry
        // must land in `hiddenTokens` for the factory denom and skip the
        // visible row (here we pre-seed the visible coin so the routing
        // de-dupes rather than hitting CoinFactory).
        let vault = TestStore.makeVault()

        // Pre-seed the curated USTC so the visible branch dedupes (we
        // can't exercise `CoinFactory.create` without real key material).
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

        // Native fee coin so `applyCosmosDiscoveredTokens` has a real
        // `Coin` to lift the chain off.
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

        // USTC was already visible — no duplicate row.
        let ustcRows = vault.coins.filter { $0.ticker == "USTC" }
        XCTAssertEqual(ustcRows.count, 1, "Visible USTC must remain a single row across discovery")

        // Factory denom landed as a HiddenToken, not as a visible coin.
        XCTAssertEqual(vault.hiddenTokens.count, 1)
        XCTAssertEqual(vault.hiddenTokens.first?.ticker, "xyz")
        XCTAssertFalse(
            vault.coins.contains(where: { $0.ticker == "xyz" }),
            "Hidden denom must NOT appear in Vault.coins"
        )

        // Second pass — idempotency on the full routing layer.
        CoinService.applyCosmosDiscoveredTokens(discovered: discovered, nativeToken: nativeCoin, to: vault)
        XCTAssertEqual(vault.coins.filter { $0.ticker == "USTC" }.count, 1)
        XCTAssertEqual(vault.hiddenTokens.count, 1, "Second discovery pass must NOT duplicate hidden rows")
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
