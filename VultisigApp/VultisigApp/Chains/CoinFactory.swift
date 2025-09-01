//
//  AccountFactory.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 20.06.2024.
//

import Foundation
import WalletCore
import CryptoKit

struct CoinFactory {
    private init() { }
    static func create(asset: CoinMeta, publicKeyECDSA: String, publicKeyEdDSA: String, hexChainCode: String) throws -> Coin {
        let publicKey = try publicKey(asset: asset, publicKeyECDSA: publicKeyECDSA, publicKeyEdDSA: publicKeyEdDSA, hexChainCode: hexChainCode)
        
        var address: String
        switch asset.chain {
        case .mayaChain:
            let anyAddress = AnyAddress(publicKey: publicKey, coin: .thorchain, hrp: "maya")
            address = anyAddress.description
        case .cardano:
            // Always create Enterprise address to avoid "stake address" component
            // Use WalletCore's proper Blake2b hashing for deterministic results across all devices
            address = try createCardanoEnterpriseAddress(spendingKeyHex: publicKeyEdDSA)
            
            // Validate Cardano address using WalletCore's own validation
            guard let _ = AnyAddress(string: address, coin: .cardano) else {
                throw Errors.invalidPublicKey(pubKey: "WalletCore validation failed for Cardano address: \(address)")
            }
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
    
    
    
    static func publicKey(asset: CoinMeta, publicKeyECDSA: String, publicKeyEdDSA: String, hexChainCode: String) throws -> PublicKey {
        switch asset.chain.signingKeyType {
        case .EdDSA:
            
            if asset.chain == .cardano {
                // For Cardano, we still need to create a proper PublicKey for transaction signing
                // even though we're creating the address manually
                let cardanoExtendedKey = try createCardanoExtendedKey(
                    spendingKeyHex: publicKeyEdDSA,
                    chainCodeHex: hexChainCode
                )
                
                // Create ed25519Cardano public key
                guard let cardanoKey = PublicKey(data: cardanoExtendedKey, type: .ed25519Cardano) else {
                    print("Failed to create ed25519Cardano key from properly structured data")
                    throw Errors.invalidPublicKey(pubKey: "Failed to create Cardano extended key")
                }
                
                return cardanoKey
            }
            
            guard
                let pubKeyData = Data(hexString: publicKeyEdDSA),
                let publicKey = PublicKey(data: pubKeyData, type: .ed25519) else {
                throw Errors.invalidPublicKey(pubKey: publicKeyEdDSA)
            }
            return publicKey
            
        case .ECDSA:
            let derivedKey = PublicKeyHelper.getDerivedPubKey(
                hexPubKey: publicKeyECDSA,
                hexChainCode: hexChainCode,
                derivePath: asset.coinType.derivationPath()
            )
            
            guard
                let pubKeyData = Data(hexString: derivedKey),
                let publicKey = PublicKey(data: pubKeyData, type: .secp256k1) else {
                throw Errors.invalidPublicKey(pubKey: publicKeyECDSA)
            }
            
            if asset.coinType == .tron {
                return publicKey.uncompressed
            }
            
            return publicKey
        }
    }
    
}

