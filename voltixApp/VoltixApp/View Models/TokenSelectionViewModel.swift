//
//  TokenSelectionViewModel.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-11.
//

import Foundation
import OSLog

@MainActor 
class TokenSelectionViewModel: ObservableObject {
    @Published var groupedAssets: [String: [Asset]] = [:]
    @Published var selection = Set<Asset>()
    
    private let logger = Logger(subsystem: "assets-list", category: "view")
    
    func setData(for vault: Vault) {
        groupAssets()
        checkSelected(for: vault)
    }
    
    private func groupAssets() {
        groupedAssets = [:]
        groupedAssets = Dictionary(grouping: TokensStore.TokenSelectionAssets) { $0.chainName }
    }
    
    private func checkSelected(for vault: Vault) {
        selection = Set<Asset>()
        for item in vault.coins {
            if let asset = TokensStore.TokenSelectionAssets.first(where: { $0.ticker == item.ticker }) {
                selection.insert(asset)
            }
        }
    }
    
    func handleSelection(isSelected: Bool, asset: Asset) {
        if isSelected {
            selection.insert(asset)
        } else {
            selection.remove(asset)
        }
    }
    
    func saveAssets(for vault: Vault) {
        addAssets(to: vault)
        removeAssets(for: vault)
    }
    
    private func addAssets(to vault: Vault) {
        for asset in selection {
            if vault.coins.contains(where: { $0.ticker == asset.ticker }) {
                print("Coin already exists")
            } else {
                addToChain(asset: asset, to: vault)
            }
        }
    }
    
    private func removeAssets(for vault: Vault) {
        for coin in vault.coins {
            if !selection.contains(where: { $0.ticker == coin.ticker }) {
                vault.coins = vault.coins.filter { $0 != coin }
            }
        }
    }
    
    private func addToChain(asset: Asset, to vault: Vault) {
        switch asset.chainName {
            case Chain.THORChain.name:
                let runeCoinResult = THORChainHelper.getRUNECoin(hexPubKey: vault.pubKeyECDSA, hexChainCode: vault.hexChainCode)
                switch runeCoinResult {
                    case .success(let coin):
                        vault.coins.append(coin)
                    case .failure(let error):
                        logger.info("fail to get thorchain address,error:\(error.localizedDescription)")
                }
            case Chain.Ethereum.name:
                let coinResult = EthereumHelper.getEthereum(hexPubKey: vault.pubKeyECDSA, hexChainCode: vault.hexChainCode)
                switch coinResult {
                    case .success(let coin):
                            // all coins on Ethereum share the same address
                        if coin.ticker == "Ethereum" {
                            vault.coins.append(coin)
                        } else {
                            let newCoin = Coin(chain: coin.chain, ticker: asset.ticker, logo: asset.image, address: coin.address, hexPublicKey: coin.hexPublicKey, feeUnit: "GWEI", contractAddress: asset.contractAddress)
                            vault.coins.append(newCoin)
                        }
                    case .failure(let error):
                        logger.info("fail to get ethereum address,error:\(error.localizedDescription)")
                }
            case Chain.Bitcoin.name:
                let coinResult = UTXOChainsHelper(coin: .bitcoin, vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode).getCoin()
                switch coinResult {
                    case .success(let btc):
                        vault.coins.append(btc)
                    case .failure(let err):
                        logger.info("fail to get bitcoin address,error:\(err.localizedDescription)")
                }
            case Chain.BitcoinCash.name:
                let coinResult = UTXOChainsHelper(coin: .bitcoinCash, vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode).getCoin()
                switch coinResult {
                    case .success(let bch):
                        vault.coins.append(bch)
                    case .failure(let err):
                        logger.info("fail to get bitcoin bash address,error:\(err.localizedDescription)")
                }
            case Chain.Litecoin.name:
                let coinResult = UTXOChainsHelper(coin: .litecoin, vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode).getCoin()
                switch coinResult {
                    case .success(let ltc):
                        vault.coins.append(ltc)
                    case .failure(let err):
                        logger.info("fail to get litecoin address,error:\(err.localizedDescription)")
                }
            case Chain.Dogecoin.name:
                let coinResult = UTXOChainsHelper(coin: .dogecoin, vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode).getCoin()
                switch coinResult {
                    case .success(let doge):
                        vault.coins.append(doge)
                    case .failure(let err):
                        logger.info("fail to get dogecoin address,error:\(err.localizedDescription)")
                }
            case Chain.Solana.name:
                print("\(Chain.Solana.name) > \(vault.pubKeyEdDSA) > \(vault.hexChainCode)")
                let coinResult = SolanaHelper.getSolana(hexPubKey: vault.pubKeyEdDSA, hexChainCode: vault.hexChainCode)
                switch coinResult {
                    case .success(let sol):
                        vault.coins.append(sol)
                    case .failure(let err):
                        logger.info("fail to get solana address,error:\(err.localizedDescription)")
                }
            default:
                print("do it later")
        }
    }
}
