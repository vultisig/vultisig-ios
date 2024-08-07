//
//  AddressService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 06/08/24.
//

import Foundation
import SwiftUI
import WalletCore

public class AddressService {
        
    static func resolveDomaninAddress(address: String, chain: Chain) async -> String {
        
        do {
            
            guard address.isNameService() else {
                return address
            }
            
            let ensName = address
            let namehash = ensName.namehash()
            print("Namehash for \(ensName): \(namehash)")
            
            let factory = try EvmServiceFactory.getService(forChain: chain)
            let address = try await factory.resolveENS(ensName: ensName)
            
            print("Resolved address \(address)")
            
            return address
            
        } catch {
            
            print("Error to extract the DOMAIN ADDRESS: \(error.localizedDescription)")
            return address
            
        }
    }
    
    static func validateAddress(address: String, chain: Chain) -> Bool {
        
        if address.isNameService() {
            return true
        }
        
        if chain == .mayaChain {
            return AnyAddress.isValidBech32(string: address, coin: .thorchain, hrp: "maya")
        }
        
        return chain.coinType.validate(address: address)
        
    }
    
    static func validateAddress(coin: CoinMeta, address: String) -> Bool {
        
        if address.isNameService() {
            return true
        }
        
        if coin.chain == .mayaChain {
            return AnyAddress.isValidBech32(string: address, coin: .thorchain, hrp: "maya")
        }
        
        return coin.coinType.validate(address: address)
    }
    
    func validateAddress(address: String, group: GroupedChain) -> Bool {
        
        if address.isNameService() {
            return true
        }
        
        let firstCoinOptional = group.coins.first
        if let firstCoin = firstCoinOptional {
            if firstCoin.chain == .mayaChain {
                return AnyAddress.isValidBech32(string: address, coin: .thorchain, hrp: "maya")
            }
            return firstCoin.coinType.validate(address: address)
        }
        
        return false
    }
    
}
