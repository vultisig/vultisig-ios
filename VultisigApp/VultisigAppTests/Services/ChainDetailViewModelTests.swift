//
//  ChainDetailViewModelTests.swift
//  VultisigAppTests
//
//  Created by Gaston Mazzeo on 20/04/2026.
//

@testable import VultisigApp
import XCTest

@MainActor
final class ChainDetailViewModelTests: XCTestCase {

    func test_tokens_excludesDefiOnly() {
        let native = makeCoin(ticker: "RUNE", chain: .thorChain, isNative: true)
        let tcy = makeCoin(ticker: "TCY", chain: .thorChain, isNative: false)
        let stcy = makeCoin(ticker: "STCY", chain: .thorChain, isNative: false)

        let vault = Vault(name: "test")
        vault.coins = [native, tcy, stcy]

        let viewModel = ChainDetailViewModel(vault: vault, nativeCoin: native)

        let tickers = viewModel.tokens.map { $0.ticker }
        XCTAssertEqual(tickers.count, 2)
        XCTAssertTrue(tickers.contains("RUNE"))
        XCTAssertTrue(tickers.contains("TCY"))
        XCTAssertFalse(tickers.contains("STCY"))
    }

    func test_tokens_filtersByChain() {
        let rune = makeCoin(ticker: "RUNE", chain: .thorChain, isNative: true)
        let btc = makeCoin(ticker: "BTC", chain: .bitcoin, isNative: true)
        let eth = makeCoin(ticker: "ETH", chain: .ethereum, isNative: true)

        let vault = Vault(name: "test")
        vault.coins = [rune, btc, eth]

        let viewModel = ChainDetailViewModel(vault: vault, nativeCoin: rune)

        XCTAssertEqual(viewModel.tokens.count, 1)
        XCTAssertEqual(viewModel.tokens.first?.ticker, "RUNE")
    }

    func test_tokens_nativeFirst() {
        let native = makeCoin(ticker: "RUNE", chain: .thorChain, isNative: true)
        let tcy = makeCoin(ticker: "TCY", chain: .thorChain, isNative: false)

        let vault = Vault(name: "test")
        vault.coins = [tcy, native]

        let viewModel = ChainDetailViewModel(vault: vault, nativeCoin: native)

        XCTAssertEqual(viewModel.tokens.first?.ticker, "RUNE")
    }

    func test_filteredTokens_emptySearchReturnsAllTokens() {
        let native = makeCoin(ticker: "RUNE", chain: .thorChain, isNative: true)
        let tcy = makeCoin(ticker: "TCY", chain: .thorChain, isNative: false)

        let vault = Vault(name: "test")
        vault.coins = [native, tcy]

        let viewModel = ChainDetailViewModel(vault: vault, nativeCoin: native)
        viewModel.searchText = ""

        XCTAssertEqual(viewModel.filteredTokens.count, 2)
    }

    func test_filteredTokens_searchIsCaseInsensitive() {
        let native = makeCoin(ticker: "RUNE", chain: .thorChain, isNative: true)
        let tcy = makeCoin(ticker: "TCY", chain: .thorChain, isNative: false)

        let vault = Vault(name: "test")
        vault.coins = [native, tcy]

        let viewModel = ChainDetailViewModel(vault: vault, nativeCoin: native)
        viewModel.searchText = "tcy"

        XCTAssertEqual(viewModel.filteredTokens.count, 1)
        XCTAssertEqual(viewModel.filteredTokens.first?.ticker, "TCY")
    }

    func test_filteredTokens_excludesDefiOnlyEvenWhenMatchingSearch() {
        let native = makeCoin(ticker: "RUNE", chain: .thorChain, isNative: true)
        let stcy = makeCoin(ticker: "STCY", chain: .thorChain, isNative: false)

        let vault = Vault(name: "test")
        vault.coins = [native, stcy]

        let viewModel = ChainDetailViewModel(vault: vault, nativeCoin: native)
        viewModel.searchText = "stcy"

        XCTAssertTrue(viewModel.filteredTokens.isEmpty)
    }

    // MARK: - qbtcClaimBitcoinCoin (claim entry-point BTC resolution)

    /// Valid keys that derive a Bitcoin (ECDSA) address via WalletCore.
    private static let pubKeyECDSA = "023e4b76861289ad4528b33c2fd21b3a5160cd37b3294234914e21efb6ed4a452b"
    private static let hexChainCode = "c9b189a8232b872b8d9ccd867d0db316dd10f56e729c310fe072adf5fd204ae7"

    func test_qbtcClaimBitcoinCoin_onBitcoinScreenReturnsNativeCoin() {
        let btc = makeCoin(ticker: "BTC", chain: .bitcoin, isNative: true)
        let vault = Vault(name: "test")
        vault.coins = [btc]

        let viewModel = ChainDetailViewModel(vault: vault, nativeCoin: btc)

        XCTAssertEqual(viewModel.qbtcClaimBitcoinCoin()?.chain, .bitcoin)
    }

    func test_qbtcClaimBitcoinCoin_onQbtcScreenUsesEnabledBtc() {
        let btc = makeCoin(ticker: "BTC", chain: .bitcoin, isNative: true)
        let qbtc = makeCoin(ticker: "QBTC", chain: .qbtc, isNative: true)
        let vault = Vault(name: "test")
        vault.coins = [btc, qbtc]

        let viewModel = ChainDetailViewModel(vault: vault, nativeCoin: qbtc)

        XCTAssertEqual(viewModel.qbtcClaimBitcoinCoin()?.address, btc.address)
    }

    /// On the QBTC screen with the Bitcoin chain not enabled, the BTC coin
    /// is derived in-memory so the Claim entry point still appears.
    func test_qbtcClaimBitcoinCoin_derivesBtcWhenChainNotEnabled() {
        let qbtc = makeCoin(ticker: "QBTC", chain: .qbtc, isNative: true)
        let vault = Vault(name: "test")
        vault.pubKeyECDSA = Self.pubKeyECDSA
        vault.hexChainCode = Self.hexChainCode
        vault.coins = [qbtc]

        let viewModel = ChainDetailViewModel(vault: vault, nativeCoin: qbtc)

        let derived = viewModel.qbtcClaimBitcoinCoin()
        XCTAssertEqual(derived?.chain, .bitcoin)
        XCTAssertEqual(derived?.isNativeToken, true)
        XCTAssertFalse(derived?.address.isEmpty ?? true)
    }

    // MARK: - Helpers

    private func makeCoin(ticker: String, chain: Chain, isNative: Bool) -> Coin {
        let meta = CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: "",
            decimals: 8,
            priceProviderId: "",
            contractAddress: "",
            isNativeToken: isNative
        )
        return Coin(asset: meta, address: "test", hexPublicKey: "test")
    }
}
