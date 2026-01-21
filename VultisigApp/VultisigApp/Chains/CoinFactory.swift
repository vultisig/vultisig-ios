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
    static func create(
        asset: CoinMeta,
        publicKeyECDSA: String,
        publicKeyEdDSA: String,
        hexChainCode: String,
        isDerived: Bool
    ) throws -> Coin {
        let publicKey = try publicKey(
            chain: asset.chain,
            publicKeyECDSA: publicKeyECDSA,
            publicKeyEdDSA: publicKeyEdDSA,
            hexChainCode: hexChainCode,
            isDerived: isDerived
        )
        
        let address = try generateAddress(
            chain: asset.chain,
            publicKey: publicKey,
            publicKeyEdDSA: publicKeyEdDSA
        )
        
        return Coin(asset: asset, address: address, hexPublicKey: publicKey.data.hexString)
    }
    
    static func generateAddress(
        chain: Chain,
        publicKeyECDSA: String,
        publicKeyEdDSA: String,
        hexChainCode: String,
        isDerived: Bool
    ) throws -> String {
        let publicKey = try publicKey(
            chain: chain,
            publicKeyECDSA: publicKeyECDSA,
            publicKeyEdDSA: publicKeyEdDSA,
            hexChainCode: hexChainCode,
            isDerived: isDerived
        )
        
        return try generateAddress(
            chain: chain,
            publicKey: publicKey,
            publicKeyEdDSA: publicKeyEdDSA
        )
    }
    
    static func generateAddress(
        chain: Chain,
        publicKey: PublicKey,
        publicKeyEdDSA: String
    ) throws -> String {
        var address: String
        switch chain {
        case .mayaChain:
            let anyAddress = AnyAddress(publicKey: publicKey, coin: .thorchain, hrp: "maya")
            address = anyAddress.description
        case .thorChainStagenet:
            let anyAddress = AnyAddress(publicKey: publicKey, coin: .thorchain, hrp: "sthor")
            address = anyAddress.description
        case .cardano:
            // Always create Enterprise address to avoid "stake address" component
            // Use WalletCore's proper Blake2b hashing for deterministic results across all devices
            address = try createCardanoEnterpriseAddress(spendingKeyHex: publicKeyEdDSA)
            
            // Validate Cardano address using WalletCore's own validation
            guard AnyAddress(string: address, coin: .cardano) != nil else {
                throw Errors.invalidPublicKey(pubKey: "WalletCore validation failed for Cardano address: \(address)")
            }
        default:
            address = chain.coinType.deriveAddressFromPublicKey(publicKey: publicKey)
        }
        
        if chain == .bitcoinCash {
            address = address.replacingOccurrences(of: "bitcoincash:", with: "")
        }
        
        return address
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
    
    static func publicKey(
        chain: Chain,
        publicKeyECDSA: String,
        publicKeyEdDSA: String,
        hexChainCode: String,
        isDerived: Bool
    ) throws -> PublicKey {
        switch chain.signingKeyType {
        case .EdDSA:
            
            if chain == .cardano {
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
            let derivedKey = isDerived ? publicKeyECDSA : PublicKeyHelper.getDerivedPubKey(
                hexPubKey: publicKeyECDSA,
                hexChainCode: hexChainCode,
                derivePath: chain.coinType.derivationPath()
            )
        
            guard
                let pubKeyData = Data(hexString: derivedKey),
                let publicKey = PublicKey(data: pubKeyData, type: .secp256k1) else {
                throw Errors.invalidPublicKey(pubKey: publicKeyECDSA)
            }
            
            if chain.coinType == .tron {
                return publicKey.uncompressed
            }
            
            return publicKey
        }
    }
    
}
