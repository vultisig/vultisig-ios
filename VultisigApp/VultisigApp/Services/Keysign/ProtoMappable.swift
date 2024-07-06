//
//  MappablePayload.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 01.07.2024.
//

import Foundation
import SwiftProtobuf
import VultisigCommonData

protocol ProtoMappable {
    associatedtype ProtoType: SwiftProtobuf.Message
    init(protobuf: ProtoType, vault: Vault) throws
    func mapToProtobuff() -> ProtoType
}

enum ProtoMappableError: Error {
    case coinNotFound
    case blockchainSpecificNotFound
}

struct ProtoCoinResolver {

    static func resolve(vault: Vault, coin: VSCoin) throws -> Coin {
        guard let coin = vault.coins.first(where: { $0.chain.name == coin.chain && $0.ticker == coin.ticker }) else {
            throw ProtoMappableError.coinNotFound
        }

        return coin
    }

    static func proto(from coin: Coin) -> VSCoin {
        return .with {
            $0.chain = coin.chain.name
            $0.ticker = coin.ticker
            $0.address = coin.address
            $0.contractAddress = coin.contractAddress
        }
    }
}
