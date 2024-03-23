	//
	//  CoinsList.swift
	//  VoltixApp
	//

import OSLog
import SwiftData
import SwiftUI
import WalletCore
//TODO: Remove the old view
private let logger = Logger(subsystem: "assets-list", category: "view")
struct AssetsList: View {
	@EnvironmentObject var appState: ApplicationState
	@State private var assets = [
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
	@State private var selection = Set<Asset>()
	@State private var expandedGroups: Set<String> = Set()
	@State var editMode = EditMode.active
	
		// Computed property to group assets by chainName
	private var groupedAssets: [String: [Asset]] {
		Dictionary(grouping: assets) { $0.chainName }
	}
	
		// Automatically expand groups that contain selected assets
	private func updateExpandedGroups() {
		for (chainName, assets) in groupedAssets {
			if assets.contains(where: selection.contains) {
				expandedGroups.insert(chainName)
			}
		}
	}
	
	var body: some View {
		List {
//			ForEach(groupedAssets.keys.sorted(), id: \.self) { chainName in
//				Section(header: HStack {
//					Text(chainName)
//					Spacer()
//					Image(systemName: expandedGroups.contains(chainName) ? "chevron.up" : "chevron.down")
//				}
//					.contentShape(Rectangle())
//					.onTapGesture {
//						if expandedGroups.contains(chainName) {
//							expandedGroups.remove(chainName)
//						} else {
//							expandedGroups.insert(chainName)
//						}
//					}
//				) {
//					if expandedGroups.contains(chainName) {
//						ForEach(groupedAssets[chainName] ?? [], id: \.self) { asset in
//							HStack {
//								Text("\(asset.chainName) - \(asset.ticker)")
//								Spacer()
//								if selection.contains(asset) {
//									Image(systemName: "checkmark")
//								}
//							}
//							.padding(.leading, asset.contractAddress != nil ? 20 : 0) // Add padding if it's a child token
//							.onTapGesture {
//								if selection.contains(asset) {
//									selection.remove(asset)
//								} else {
//									selection.insert(asset)
//								}
//							}
//						}
//					}
//				}
//			}
		}
		.environment(\.editMode, $editMode)
		.navigationTitle("select assets")
        
		.onChange(of: selection) { _ in
			updateExpandedGroups()
		}
		.onAppear {
			updateExpandedGroups()
			guard let vault = appState.currentVault else {
				print("current vault is nil")
				return
			}
			for item in vault.coins {
				let asset = assets.first(where: { $0.ticker == item.ticker })
				if let asset {
					selection.insert(asset)
				}
			}
		}
		
	}
}

#Preview {
	AssetsList()
	.environmentObject(ApplicationState())
}
