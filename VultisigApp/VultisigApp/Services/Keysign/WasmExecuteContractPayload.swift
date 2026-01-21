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
    let coins: [CosmosCoin]

    init(senderAddress: String, contractAddress: String, executeMsg: String, coins: [CosmosCoin]) {
        self.senderAddress = senderAddress
        self.contractAddress = contractAddress
        self.executeMsg = executeMsg
        self.coins = coins
    }

    init?(proto: VSWasmExecuteContractPayload) throws {
        guard proto.senderAddress.isNotEmpty, proto.contractAddress.isNotEmpty else {
            return nil
        }
        self.senderAddress = proto.senderAddress
        self.contractAddress = proto.contractAddress
        self.executeMsg = proto.executeMsg
        self.coins = proto.coins.compactMap { CosmosCoin(proto: $0) }
    }

    func mapToProtobuff() -> VSWasmExecuteContractPayload {
        .with {
            $0.senderAddress = self.senderAddress
            $0.executeMsg = self.executeMsg
            $0.contractAddress = self.contractAddress
            $0.coins = self.coins.map { $0.mapToProtobuff() }
        }
    }
}
