//
//  WasmExecuteContractPayload.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 25/07/2025.
//

import VultisigCommonData

struct WasmExecuteContractPayload: Codable, Hashable {
    let senderAddress: String
    let contractAddress: String
    let executeMsg: String
    let coins: [Coin]
    
    init(senderAddress: String, contractAddress: String, executeMsg: String, coins: [Coin]) {
        self.senderAddress = senderAddress
        self.contractAddress = contractAddress
        self.executeMsg = executeMsg
        self.coins = coins
    }
    
    init?(proto: VSWasmExecuteContractPayload) throws {
        guard proto.senderAddress.isNotEmpty else {
            return nil
        }
        self.senderAddress = proto.senderAddress
        self.contractAddress = proto.contractAddress
        self.executeMsg = proto.executeMsg
        self.coins = try proto.coins.map { try ProtoCoinResolver.resolve(coin: $0) }
    }
    
    func mapToProtobuff() -> VSWasmExecuteContractPayload {
        .with {
            $0.senderAddress = self.senderAddress
            $0.executeMsg = self.executeMsg
            $0.contractAddress = self.contractAddress
            $0.coins = self.coins.map { coin in ProtoCoinResolver.proto(from: coin) }
        }
    }
}
