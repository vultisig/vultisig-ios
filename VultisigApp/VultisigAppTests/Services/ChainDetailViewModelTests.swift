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
