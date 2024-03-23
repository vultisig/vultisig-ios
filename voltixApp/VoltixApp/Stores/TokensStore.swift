	//
	//  TokenSelectionAssetsStore.swift
	//  VoltixApp
	//
	//  Created by Amol Kumar on 2024-03-13.
	//

import Foundation

class TokensStore {
	static var TokenSelectionAssets = [
		Asset(ticker: "BTC", chainName: "Bitcoin", image: "btc", chainType: .UTXO, priceProviderId: "bitcoin", tokenInfo: nil),
		Asset(ticker: "BCH", chainName: "Bitcoin-Cash", image: "bch", chainType: .UTXO, priceProviderId: "bitcoin-cash", tokenInfo: nil),
		Asset(ticker: "LTC", chainName: "Litecoin", image: "ltc", chainType: .UTXO, priceProviderId: "litecoin", tokenInfo: nil),
		Asset(ticker: "DOGE", chainName: "Dogecoin", image: "doge", chainType: .UTXO, priceProviderId: "dogecoin", tokenInfo: nil),
		Asset(ticker: "RUNE", chainName: "THORChain", image: "rune", chainType: .THORChain, priceProviderId: "thorchain", tokenInfo: nil),
		// Ethereum chain
		Asset(ticker: "ETH", chainName: "Ethereum", image: "eth", chainType: .EVM, priceProviderId: "ethereum", tokenInfo: nil),
		Asset(ticker: "USDC", chainName: "Ethereum", image: "usdc", chainType: .EVM, priceProviderId: "usd-coin", tokenInfo: Token(rawBalance: "", address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", name: "USD Coin", decimals: "6", symbol: "USDC")),
		Asset(ticker: "USDT", chainName: "Ethereum", image: "usdt", chainType: .EVM, priceProviderId: "tether", tokenInfo: Token(rawBalance: "", address: "0xdac17f958d2ee523a2206206994597c13d831ec7", name: "Tether USD", decimals: "6", symbol: "USDT")),
		Asset(ticker: "UNI", chainName: "Ethereum", image: "uni", chainType: .EVM, priceProviderId: "uniswap", tokenInfo: Token(rawBalance: "", address: "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984", name: "Uniswap", decimals: "18", symbol: "UNI")),
		Asset(ticker: "MATIC", chainName: "Ethereum", image: "matic", chainType: .EVM, priceProviderId: "polygon", tokenInfo: Token(rawBalance: "", address: "0x7d1afa7b718fb893db30a3abc0cfc608aacfebb0", name: "Polygon", decimals: "18", symbol: "MATIC")),
		Asset(ticker: "WBTC", chainName: "Ethereum", image: "wbtc", chainType: .EVM, priceProviderId: "wrapped-bitcoin", tokenInfo: Token(rawBalance: "", address: "0x2260fac5e5542a773aa44fbcfedf7c193bc2c599", name: "Wrapped Bitcoin", decimals: "8", symbol: "WBTC")),
		Asset(ticker: "LINK", chainName: "Ethereum", image: "link", chainType: .EVM, priceProviderId: "chainlink", tokenInfo: Token(rawBalance: "", address: "0x514910771af9ca656af840dff83e8264ecf986ca", name: "Chainlink", decimals: "18", symbol: "LINK")),
		Asset(ticker: "FLIP", chainName: "Ethereum", image: "flip", chainType: .EVM, priceProviderId: "chainflip", tokenInfo: Token(rawBalance: "", address: "0x826180541412d574cf1336d22c0c0a287822678a", name: "Chainflip", decimals: "18", symbol: "FLIP")),
		// Solana chain
		Asset(ticker: "SOL", chainName: "Solana", image: "solana", chainType: .Solana, priceProviderId: "solana", tokenInfo: nil)
	]
}
