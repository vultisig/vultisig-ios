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

    static func create(asset: CoinMeta, hexPubKey: String, hexChainCode: String) throws -> Coin {
        let derivePubKey = PublicKeyHelper.getDerivedPubKey(
            hexPubKey: hexPubKey,
            hexChainCode: hexChainCode,
            derivePath: asset.coinType.derivationPath()
        )

        guard 
            let pubKeyData = Data(hexString: derivePubKey),
            let publicKey = PublicKey(data: pubKeyData, type: .secp256k1) else {
            throw Errors.invalidPublicKey(derivePubKey: derivePubKey)
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
        case invalidPublicKey(derivePubKey: String)

        var errorDescription: String? {
            switch self {
            case .invalidPublicKey(let derivePubKey):
                return "Public key: \(derivePubKey) is invalid"
            }
        }
    }
}
