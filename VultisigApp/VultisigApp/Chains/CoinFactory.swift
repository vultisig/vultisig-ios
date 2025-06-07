//
//  AccountFactory.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 20.06.2024.
//

import Foundation
import WalletCore

struct CoinFactory {
    
    private init() { }
    
    static func create(asset: CoinMeta, vault: Vault) throws -> Coin {
        let publicKey = try publicKey(asset: asset, vault: vault)
        
        var address: String
        switch asset.chain {
        case .mayaChain:
            let anyAddress = AnyAddress(publicKey: publicKey, coin: .thorchain, hrp: "maya")
            address = anyAddress.description
        case .cardano:
            let anyAddress = AnyAddress(publicKey: publicKey, coin: .cardano)
            address = anyAddress.description
        default:
            address = asset.coinType.deriveAddressFromPublicKey(publicKey: publicKey)
        }
        
        if asset.chain == .bitcoinCash {
            address = address.replacingOccurrences(of: "bitcoincash:", with: "")
        }
        
        return Coin(asset: asset, address: address, hexPublicKey: publicKey.data.hexString)
    }
}

extension CoinFactory {
    
    enum Errors: Error, LocalizedError {
        case invalidPublicKey(pubKey: String)
        
        var errorDescription: String? {
            switch self {
            case .invalidPublicKey(let pubKey):
                return "Public key: \(pubKey) is invalid"
            }
        }
    }
    
    static func publicKey(asset: CoinMeta, vault: Vault) throws -> PublicKey {
        switch asset.chain.signingKeyType {
        case .EdDSA:
            
            if asset.chain == .cardano {
                
                guard
                    let pubKeyData = Data(hexString: vault.pubKeyEdDSA),
                    let publicKey = PublicKey(data: pubKeyData, type: .ed25519Cardano) else {
                    
                    print("Public key: \(vault.pubKeyEdDSA) is invalid for ADA chain")
                    throw Errors.invalidPublicKey(pubKey: vault.pubKeyEdDSA)
                }
                return publicKey
                
            }
            
            guard
                let pubKeyData = Data(hexString: vault.pubKeyEdDSA),
                let publicKey = PublicKey(data: pubKeyData, type: .ed25519) else {
                throw Errors.invalidPublicKey(pubKey: vault.pubKeyEdDSA)
            }
            return publicKey
            
        case .ECDSA:
            let derivedKey = PublicKeyHelper.getDerivedPubKey(
                hexPubKey: vault.pubKeyECDSA,
                hexChainCode: vault.hexChainCode,
                derivePath: asset.coinType.derivationPath()
            )
            
            guard
                let pubKeyData = Data(hexString: derivedKey),
                let publicKey = PublicKey(data: pubKeyData, type: .secp256k1) else {
                throw Errors.invalidPublicKey(pubKey: vault.pubKeyECDSA)
            }
            
            if asset.coinType == .tron {
                return publicKey.uncompressed
            }
            
            return publicKey
        }
    }
    
}

