//
//  Cosmos+ProtoMappable.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 29/07/2025.
//

import VultisigCommonData

enum SignData: Codable, Hashable {
    case signAmino(SignAmino)
    case signDirect(SignDirect)
    case signSolana(SignSolana)

    init(proto: VSKeysignPayload.OneOf_SignData) {
        switch proto {
        case .signAmino(let vSSignAmino):
            self = .signAmino(SignAmino(proto: vSSignAmino))
        case .signDirect(let vSSignDirect):
            self = .signDirect(SignDirect(proto: vSSignDirect))
        case .signSolana(let vSSignSolana):
            self = .signSolana(SignSolana(proto: vSSignSolana))
        }
    }

    func mapToProtobuff() -> VSKeysignPayload.OneOf_SignData {
        switch self {
        case .signAmino(let vSSignAmino):
            return .signAmino(vSSignAmino.mapToProtobuff())
        case .signDirect(let vSSignDirect):
            return .signDirect(vSSignDirect.mapToProtobuff())
        case .signSolana(let vSSignSolana):
            return .signSolana(vSSignSolana.mapToProtobuff())
        }
    }
}

struct CosmosCoin: Codable, Hashable {
    let amount: String
    let denom: String

    init(proto: VSCosmosCoin) {
        self.amount = proto.amount
        self.denom = proto.denom
    }

    init(amount: String, denom: String) {
        self.amount = amount
        self.denom = denom
    }

    func mapToProtobuff() -> VSCosmosCoin {
        .with {
            $0.amount = self.amount
            $0.denom = self.denom
        }
    }
}

struct SignDirect: Codable, Hashable {
    let bodyBytes: String
    let authInfoBytes: String
    let chainID: String
    let accountNumber: String

    static let empty: SignDirect = .init(
        bodyBytes: "",
        authInfoBytes: "",
        chainID: "",
        accountNumber: ""
    )

    init(proto: VSSignDirect) {
        self.bodyBytes = proto.bodyBytes
        self.authInfoBytes = proto.authInfoBytes
        self.chainID = proto.chainID
        self.accountNumber = proto.accountNumber
    }

    init(
        bodyBytes: String,
        authInfoBytes: String,
        chainID: String,
        accountNumber: String
    ) {
        self.bodyBytes = bodyBytes
        self.authInfoBytes = authInfoBytes
        self.chainID = chainID
        self.accountNumber = accountNumber
    }

    func mapToProtobuff() -> VSSignDirect {
        .with {
            $0.bodyBytes = bodyBytes
            $0.authInfoBytes = authInfoBytes
            $0.chainID = chainID
            $0.accountNumber = accountNumber
        }
    }
}

struct SignAmino: Codable, Hashable {
    let fee: CosmosFee
    let msgs: [CosmosMessage]

    init(proto: VSSignAmino) {
        self.fee = CosmosFee(proto: proto.fee)
        self.msgs = proto.msgs.map { CosmosMessage(proto: $0) }
    }

    init(
        fee: CosmosFee,
        msgs: [CosmosMessage]
    ) {
        self.fee = fee
        self.msgs = msgs
    }

    func mapToProtobuff() -> VSSignAmino {
        .with {
            $0.fee = fee.mapToProtobuff()
            $0.msgs = msgs.map { $0.mapToProtobuff() }
        }
    }
}

struct CosmosMessage: Codable, Hashable {
    let type: String
    let value: String

    init(proto: VSCosmosMsg) {
        self.type = proto.type
        self.value = proto.value
    }

    init(
        type: String,
        value: String
    ) {
        self.type = type
        self.value = value
    }

    func mapToProtobuff() -> VSCosmosMsg {
        .with {
            $0.type = type
            $0.value = value
        }
    }
}

struct CosmosFee: Codable, Hashable {
    let payer: String
    let granter: String
    let feePayer: String
    let amount: [CosmosCoin]
    let gas: String

    init(proto: VSCosmosFee) {
        self.payer = proto.payer
        self.granter = proto.granter
        self.feePayer = proto.feePayer
        self.amount = proto.amount.map { CosmosCoin(proto: $0) }
        self.gas = proto.gas
    }

    init(
        payer: String,
        granter: String,
        feePayer: String,
        amount: [CosmosCoin],
        gas: String
    ) {
        self.payer = payer
        self.granter = granter
        self.feePayer = feePayer
        self.amount = amount
        self.gas = gas
    }

    func mapToProtobuff() -> VSCosmosFee {
        .with {
            $0.payer = payer
            $0.granter = granter
            $0.feePayer = feePayer
            $0.amount = amount.map { $0.mapToProtobuff() }
            $0.gas = gas
        }
    }
}
