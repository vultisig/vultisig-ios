//
//  VaultDefaultCoinService.swift
//  VultisigApp
//
//  Created by Johnny Luo on 3/6/2024.
//

import Foundation
import SwiftData

class VaultDefaultCoinService {
    let context: ModelContext
    private let semaphore = DispatchSemaphore(value: 1)
    let defaultChains = [Chain.bitcoin, Chain.ethereum, Chain.thorChain, Chain.solana]
    
    init(context:ModelContext){
        self.context = context
    }
    func setDefaultCoinsOnce(vault: Vault) {
        semaphore.wait()
        Task{
            await setDefaultCoins(for: vault)
            semaphore.signal()
        }
    }
    func setDefaultCoins(for vault: Vault) async {
        // add bitcoin when the vault doesn't have any coins in it
        if vault.coins.count == 0 {
            print("set default coins for vault:\(vault.name)")
            for chain in defaultChains {
                var result: Result<Coin,Error>
                switch chain {
                case .bscChain:
                    result = EVMHelper(coinType: .smartChain).getCoin(hexPubKey: vault.pubKeyEdDSA, hexChainCode: vault.hexChainCode)
                case .bitcoin:
                    result = UTXOChainsHelper(coin: .bitcoin, vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode).getCoin()
                case .ethereum:
                    result = EVMHelper(coinType: .ethereum).getCoin(hexPubKey: vault.pubKeyECDSA, hexChainCode: vault.hexChainCode)
                case .thorChain:
                    result = THORChainHelper.getRUNECoin(hexPubKey: vault.pubKeyECDSA, hexChainCode: vault.hexChainCode)
                case .solana:
                    result = SolanaHelper.getSolana(hexPubKey: vault.pubKeyEdDSA, hexChainCode: vault.hexChainCode)
                default:
                    continue
                }
                
                switch result {
                case .success(let coin):
                    context.insert(coin)
                    vault.coins.append(coin)
                case .failure(let error):
                    print("error: \(error)")
                }
                
            }
        }
    }
}
