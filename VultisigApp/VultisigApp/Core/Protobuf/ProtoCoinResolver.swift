//
//  ProtoCoinResolver.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 07.07.2024.
//

import Foundation
import VultisigCommonData

struct ProtoCoinResolver {

    private init() { }

    static func resolve(coin: VSCoin) throws -> Coin {
        guard let chain = Chain(name: coin.chain) else {
            throw ProtoMappableError.chainNotSupport
        }
        let cm = CoinMeta(chain: chain,
                          ticker: coin.ticker,
                          logo: coin.logo,
                          decimals: Int(coin.decimals),
                          priceProviderId: coin.priceProviderID,
                          contractAddress: coin.contractAddress,
                          isNativeToken: coin.isNativeToken)
        return Coin(asset: cm, address: coin.address, hexPublicKey: coin.hexPublicKey)
    }

    static func proto(from coin: Coin) -> VSCoin {
        return .with {
            $0.decimals = Int32(coin.decimals)
            $0.hexPublicKey = coin.hexPublicKey
            $0.isNativeToken = coin.isNativeToken
            $0.priceProviderID = coin.priceProviderId
            $0.logo = coin.logo
            $0.chain = coin.chain.name
            $0.ticker = coin.ticker
            $0.address = coin.address
            $0.contractAddress = coin.contractAddress
        }
    }
}
