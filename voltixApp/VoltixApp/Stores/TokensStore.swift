//
//  TokenSelectionAssetsStore.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-13.
//

import Foundation

class TokensStore {
    static var TokenSelectionAssets = [
		Asset(ticker: "BTC", chainName: "Bitcoin", image: "btc", contractAddress: nil, chainType: .UTXO),
        Asset(ticker: "BCH", chainName: "Bitcoin-Cash", image: "bch", contractAddress: nil, chainType: .UTXO),
        Asset(ticker: "LTC", chainName: "Litecoin", image: "ltc", contractAddress: nil, chainType: .UTXO),
        Asset(ticker: "DOGE", chainName: "Dogecoin", image: "doge", contractAddress: nil, chainType: .UTXO),
        Asset(ticker: "RUNE", chainName: "THORChain", image: "rune", contractAddress: nil, chainType: .THORChain),
        // Ethereum chain
        Asset(ticker: "ETH", chainName: "Ethereum", image: "eth", contractAddress: nil, chainType: .EVM),
        Asset(ticker: "USDC", chainName: "Ethereum", image: "usdc", contractAddress: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", chainType: .EVM),
        Asset(ticker: "USDT", chainName: "Ethereum", image: "usdt", contractAddress: "0xdac17f958d2ee523a2206206994597c13d831ec7", chainType: .EVM),
        Asset(ticker: "UNI", chainName: "Ethereum", image: "uni", contractAddress: "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984", chainType: .EVM),
        Asset(ticker: "MATIC", chainName: "Ethereum", image: "matic", contractAddress: "0x7d1afa7b718fb893db30a3abc0cfc608aacfebb0", chainType: .EVM),
        Asset(ticker: "WBTC", chainName: "Ethereum", image: "wbtc", contractAddress: "0x2260fac5e5542a773aa44fbcfedf7c193bc2c599", chainType: .EVM),
        Asset(ticker: "LINK", chainName: "Ethereum", image: "link", contractAddress: "0x514910771af9ca656af840dff83e8264ecf986ca", chainType: .EVM),
        Asset(ticker: "FLIP", chainName: "Ethereum", image: "flip", contractAddress: "0x826180541412d574cf1336d22c0c0a287822678a", chainType: .EVM),//
        // Solana chain
        Asset(ticker: "SOL", chainName: "Solana", image: "solana", contractAddress: nil, chainType: .Solana)
    ]
}
