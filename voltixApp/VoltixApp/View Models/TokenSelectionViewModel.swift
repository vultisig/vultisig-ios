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
            if let asset = TokensStore.TokenSelectionAssets.first(where: { $0.ticker == asset.ticker && $0.chain == asset.chain}) {
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
            selection.contains(where: { $0.ticker == coin.ticker && $0.chain == coin.chain})
        }
        
        for asset in selection {
            if !vault.coins.contains(where: { $0.ticker == asset.ticker && $0.chain == asset.chain}) {
                addToChain(asset: asset, to: vault)
            }
        }
    }
    
    private func addToChain(asset: Coin, to vault: Vault) {
        switch asset.chain {
        case .thorChain:
            let runeCoinResult = THORChainHelper.getRUNECoin(hexPubKey: vault.pubKeyECDSA, hexChainCode: vault.hexChainCode)
            switch runeCoinResult {
            case .success(let coin):
                coin.priceProviderId = asset.priceProviderId
                vault.coins.append(coin)
            case .failure(let error):
                logger.info("fail to get thorchain address,error:\(error.localizedDescription)")
            }
        case .mayaChain:
            let cacaoCoinResult = MayaChainHelper.getMayaCoin(hexPubKey: vault.pubKeyECDSA,
                                                              hexChainCode: vault.hexChainCode,
                                                              coinTicker: asset.ticker)
            switch cacaoCoinResult {
            case .success(let coin):
                coin.priceProviderId = asset.priceProviderId
                vault.coins.append(coin)
            case .failure(let error):
                logger.info("fail to get thorchain address,error:\(error.localizedDescription)")
            }
        case .ethereum, .arbitrum, .base, .optimism, .polygon, .bscChain, .avalanche:
            
            guard let evmHelper = EVMHelper.getHelper(coin: asset) else {
                logger.info("Coin type not found on EVM helper")
                return
            }
            
            let coinResult = evmHelper.getCoin(hexPubKey: vault.pubKeyECDSA, hexChainCode: vault.hexChainCode)
            switch coinResult {
            case .success(let coin):
                
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
                                   isNativeToken: asset.isNativeToken,
                                   feeDefault: asset.feeDefault
                                   
                )
                vault.coins.append(newCoin)
                
            case .failure(let error):
                logger.info("fail to get ethereum address, error: \(error.localizedDescription)")
            }
            
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash:
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
        case .solana:
            let coinResult = SolanaHelper.getSolana(hexPubKey: vault.pubKeyEdDSA, hexChainCode: vault.hexChainCode)
            switch coinResult {
            case .success(let sol):
                sol.priceProviderId = asset.priceProviderId
                vault.coins.append(sol)
            case .failure(let err):
                logger.info("fail to get solana address,error:\(err.localizedDescription)")
            }
        case .gaiaChain:
            let coinResult = ATOMHelper().getATOMCoin(hexPubKey: vault.pubKeyECDSA, hexChainCode: vault.hexChainCode)
            switch coinResult {
            case .success(let atom):
                atom.priceProviderId = asset.priceProviderId
                vault.coins.append(atom)
            case .failure(let err):
                logger.info("fail to get solana address,error:\(err.localizedDescription)")
            }
        case .kujira:
            let coinResult = KujiraHelper().getCoin(hexPubKey: vault.pubKeyECDSA, hexChainCode: vault.hexChainCode)
            switch coinResult {
            case .success(let atom):
                atom.priceProviderId = asset.priceProviderId
                vault.coins.append(atom)
            case .failure(let err):
                logger.info("fail to get solana address,error:\(err.localizedDescription)")
            }
        }
    }
}
