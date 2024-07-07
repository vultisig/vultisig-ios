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
    case base64EncodedDataNotFound
}

struct ProtoCoinResolver {

    private init() { }

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

struct ProtoSerializer {

    private init() { }

    static func serialize<T: ProtoMappable>(_ model: T) throws -> String {
        let proto = model.mapToProtobuff()
        let compressed = try proto.serializedData()
        let compressedData = try (compressed as NSData).compressed(using: .zlib)
        let compressedDataBase64 = compressedData.base64EncodedString()
        return compressedDataBase64
    }

    static func deserialize<T: ProtoMappable>(base64EncodedString: String, vault: Vault) throws -> T {
        guard let compressedData = Data(base64Encoded: base64EncodedString) else {
            throw ProtoMappableError.base64EncodedDataNotFound
        }
        let serializedData = try (compressedData as NSData).decompressed(using: .zlib) as Data
        let proto = try T.ProtoType(serializedData: serializedData)
        let model = try T(protobuf: proto, vault: vault)
        return model
    }
}
