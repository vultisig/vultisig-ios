	//
	//  TokenSelectionViewModel.swift
	//  VoltixApp
	//
	//  Created by Amol Kumar on 2024-03-11.
	//

import Foundation
import OSLog
import WalletCore

@MainActor
class TokenSelectionViewModel: ObservableObject {
	@Published var groupedAssets: [String: [Coin]] = [:]
	@Published var selection = Set<Coin>()
	
	private let logger = Logger(subsystem: "assets-list", category: "view")
	
	func setData(for vault: Vault) {
		groupAssets()
		checkSelected(for: vault)
	}
	
	private func groupAssets() {
		groupedAssets = [:]
		groupedAssets = Dictionary(grouping: TokensStore.TokenSelectionAssets) { $0.chain.name }
	}
	
	private func checkSelected(for vault: Vault) {
		selection = Set<Coin>()
		for asset in vault.coins {
			if let asset = TokensStore.TokenSelectionAssets.first(where: { $0.ticker == asset.ticker }) {
				selection.insert(asset)
			}
		}
	}
	
	func handleSelection(isSelected: Bool, asset: Coin) {
		if isSelected {
			selection.insert(asset)
		} else {
			selection.remove(asset)
		}
	}
	
	func saveAssets(for vault: Vault) {
		vault.coins = vault.coins.filter { coin in
			selection.contains(where: { $0.ticker == coin.ticker })
		}
		
		for asset in selection {
			if !vault.coins.contains(where: { $0.ticker == asset.ticker }) {
				addToChain(asset: asset, to: vault)
			}
		}
	}
	
	private func addToChain(asset: Coin, to vault: Vault) {
		switch asset.chain.name {
			case Chain.THORChain.name:
				let runeCoinResult = THORChainHelper.getRUNECoin(hexPubKey: vault.pubKeyECDSA, hexChainCode: vault.hexChainCode)
				switch runeCoinResult {
					case .success(let coin):
						coin.priceProviderId = asset.priceProviderId ?? ""
						vault.coins.append(coin)
					case .failure(let error):
						logger.info("fail to get thorchain address,error:\(error.localizedDescription)")
				}
			case Chain.Ethereum.name:
				let coinResult = EthereumHelper.getEthereum(hexPubKey: vault.pubKeyECDSA, hexChainCode: vault.hexChainCode)
				switch coinResult {
					case .success(let coin):
						if coin.ticker == "Ethereum" {
							coin.priceProviderId = asset.priceProviderId
							vault.coins.append(coin)
						} else {
							let newCoin = Coin(chain: asset.chain,
											   ticker: asset.ticker,
											   logo: asset.logo,
											   address: coin.address,
											   priceRate: 0.0,
											   chainType: coin.chainType,
											   decimals: asset.decimals, // Assuming 18 for Ethereum-based tokens
											   hexPublicKey: coin.hexPublicKey,
											   feeUnit: asset.feeUnit,
											   priceProviderId: asset.priceProviderId ,
											   contractAddress: asset.contractAddress , // Assuming asset has a contractAddress field
											   rawBalance: "0",
											   isToken: asset.isToken)
							vault.coins.append(newCoin)
						}
					case .failure(let error):
						logger.info("fail to get ethereum address, error: \(error.localizedDescription)")
				}

			case Chain.Bitcoin.name, Chain.BitcoinCash.name, Chain.Litecoin.name, Chain.Dogecoin.name:
				guard let coinType = CoinType.from(string: asset.chain.name.replacingOccurrences(of: "-", with: "")) else {
					print("Coin type not found on Wallet Core")
					return
				}
				let coinResult = UTXOChainsHelper(coin: coinType, vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode).getCoin()
				switch coinResult {
					case .success(let btc):
						btc.priceProviderId = asset.priceProviderId
						vault.coins.append(btc)
					case .failure(let err):
						logger.info("fail to get bitcoin address,error:\(err.localizedDescription)")
				}
			case Chain.Solana.name:
				let coinResult = SolanaHelper.getSolana(hexPubKey: vault.pubKeyEdDSA, hexChainCode: vault.hexChainCode)
				switch coinResult {
					case .success(let sol):
						sol.priceProviderId = asset.priceProviderId
						vault.coins.append(sol)
					case .failure(let err):
						logger.info("fail to get solana address,error:\(err.localizedDescription)")
				}
			default:
				print("Unsupported chain: \(asset.chain.name)")
		}
	}
}
