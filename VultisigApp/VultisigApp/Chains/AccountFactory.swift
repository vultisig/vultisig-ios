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
        let hexPubKey = publicKey(asset: asset, vault: vault)

        guard 
            let pubKeyData = Data(hexString: hexPubKey),
            let publicKey = PublicKey(data: pubKeyData, type: .secp256k1) else {
            throw Errors.invalidPublicKey(pubKey: hexPubKey)
        }

        let address: String

        switch asset.chain {
        case .mayaChain:
            let anyAddress = AnyAddress(publicKey: publicKey, coin: .thorchain, hrp: "maya")
            address = anyAddress.description
        default:
            address = asset.coinType.deriveAddressFromPublicKey(publicKey: publicKey)
        }

        return Coin(asset: asset, address: address, hexPublicKey: hexPubKey)
    }
}

private extension CoinFactory {

    enum Errors: Error, LocalizedError {
        case invalidPublicKey(pubKey: String)

        var errorDescription: String? {
            switch self {
            case .invalidPublicKey(let pubKey):
                return "Public key: \(pubKey) is invalid"
            }
        }
    }

    static func publicKey(asset: CoinMeta, vault: Vault) -> String {
        switch asset.chain {
        case .solana, .sui, .polkadot:
            return vault.pubKeyEdDSA
        case .arbitrum, .avalanche, .base, .bitcoin, .bitcoinCash, .blast, .bscChain, .cronosChain, .dash, .dogecoin, .dydx, .ethereum, .gaiaChain, .kujira, .litecoin, .mayaChain, .optimism, .polygon, .thorChain, .zksync:
            return PublicKeyHelper.getDerivedPubKey(
                hexPubKey: vault.pubKeyECDSA,
                hexChainCode: vault.hexChainCode,
                derivePath: asset.coinType.derivationPath()
            )
        }
    }
}
