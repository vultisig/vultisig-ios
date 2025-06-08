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
            // Use default derivation instead of AnyAddress to avoid ed25519Cardano requirement
            address = asset.coinType.deriveAddressFromPublicKey(publicKey: publicKey)
        default:
            address = asset.coinType.deriveAddressFromPublicKey(publicKey: publicKey)
        }
        
        if asset.chain == .bitcoinCash {
            address = address.replacingOccurrences(of: "bitcoincash:", with: "")
        }
        
        // Validate Cardano address using WalletCore's own validation
        if asset.chain == .cardano {
            guard let _ = AnyAddress(string: address, coin: .cardano) else {
                throw Errors.invalidPublicKey(pubKey: "WalletCore validation failed for Cardano address: \(address)")
            }
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
    
    /// Creates a proper Cardano V2 extended key structure (128 bytes total)
    static func createCardanoExtendedKey(spendingKeyHex: String, chainCodeHex: String) throws -> Data {
        guard let spendingKeyData = Data(hexString: spendingKeyHex) else {
            throw Errors.invalidPublicKey(pubKey: "public key \(spendingKeyHex) is invalid")
        }
        guard let chainCodeData = Data(hexString: chainCodeHex) else {
            throw Errors.invalidPublicKey(pubKey: "chain code \(chainCodeHex) is invalid")
        }
        
        // Ensure we have 32-byte keys
        guard spendingKeyData.count == 32 else {
            throw Errors.invalidPublicKey(pubKey: "spending key must be 32 bytes, got \(spendingKeyData.count)")
        }
        guard chainCodeData.count == 32 else {
            throw Errors.invalidPublicKey(pubKey: "chain code must be 32 bytes, got \(chainCodeData.count)")
        }
        
        // Build 128-byte extended key following Cardano V2 specification
        var extendedKeyData = Data()
        extendedKeyData.append(spendingKeyData)     // 32 bytes: EdDSA spending key
        extendedKeyData.append(spendingKeyData)     // 32 bytes: EdDSA staking key (reuse spending key)
        extendedKeyData.append(chainCodeData)       // 32 bytes: Chain code
        extendedKeyData.append(chainCodeData)       // 32 bytes: Additional chain code
        
        // Verify we have correct 128-byte structure
        guard extendedKeyData.count == 128 else {
            throw Errors.invalidPublicKey(pubKey: "extended key must be 128 bytes, got \(extendedKeyData.count)")
        }
        
        return extendedKeyData
    }
    
    static func publicKey(asset: CoinMeta, vault: Vault) throws -> PublicKey {
        switch asset.chain.signingKeyType {
        case .EdDSA:
            
            if asset.chain == .cardano {
                // Use the helper function to create the extended key
                let cardanoExtendedKey = try createCardanoExtendedKey(
                    spendingKeyHex: vault.pubKeyEdDSA, 
                    chainCodeHex: vault.hexChainCode
                )
                
                // Create ed25519Cardano public key
                guard let cardanoKey = PublicKey(data: cardanoExtendedKey, type: .ed25519Cardano) else {
                    print("Failed to create ed25519Cardano key from properly structured data")
                    throw Errors.invalidPublicKey(pubKey: "Failed to create Cardano extended key")
                }
                
                return cardanoKey
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

