//
//  SignBitcoin.swift
//  VultisigApp
//
//  Created by gaston on 27/04/2026.
//

import Foundation
import VultisigCommonData

struct BitcoinInput: Codable, Hashable {
    let hash: String
    let index: UInt32
    let amount: Int64
    let scriptPubKey: String
    let scriptType: String
    let sighashType: UInt32?
    let isOurs: Bool
    let redeemScript: String?
    let sequence: UInt32?

    init(
        hash: String,
        index: UInt32,
        amount: Int64,
        scriptPubKey: String,
        scriptType: String,
        sighashType: UInt32? = nil,
        isOurs: Bool,
        redeemScript: String? = nil,
        sequence: UInt32? = nil
    ) {
        self.hash = hash
        self.index = index
        self.amount = amount
        self.scriptPubKey = scriptPubKey
        self.scriptType = scriptType
        self.sighashType = sighashType
        self.isOurs = isOurs
        self.redeemScript = redeemScript
        self.sequence = sequence
    }

    init(proto: VSBitcoinInput) {
        self.hash = proto.hash
        self.index = proto.index
        self.amount = proto.amount
        self.scriptPubKey = proto.scriptPubKey
        self.scriptType = proto.scriptType
        self.sighashType = proto.hasSighashType ? proto.sighashType : nil
        self.isOurs = proto.isOurs
        self.redeemScript = proto.hasRedeemScript ? proto.redeemScript : nil
        self.sequence = proto.hasSequence ? proto.sequence : nil
    }

    func mapToProtobuff() -> VSBitcoinInput {
        .with {
            $0.hash = hash
            $0.index = index
            $0.amount = amount
            $0.scriptPubKey = scriptPubKey
            $0.scriptType = scriptType
            if let sighashType {
                $0.sighashType = sighashType
            }
            $0.isOurs = isOurs
            if let redeemScript {
                $0.redeemScript = redeemScript
            }
            if let sequence {
                $0.sequence = sequence
            }
        }
    }
}

struct BitcoinOutput: Codable, Hashable {
    let amount: Int64
    let address: String
    let opReturnData: String?
    let scriptPubKey: String
    let isChange: Bool

    init(
        amount: Int64,
        address: String,
        opReturnData: String? = nil,
        scriptPubKey: String,
        isChange: Bool
    ) {
        self.amount = amount
        self.address = address
        self.opReturnData = opReturnData
        self.scriptPubKey = scriptPubKey
        self.isChange = isChange
    }

    init(proto: VSBitcoinOutput) {
        self.amount = proto.amount
        self.address = proto.address
        self.opReturnData = proto.hasOpReturnData ? proto.opReturnData : nil
        self.scriptPubKey = proto.scriptPubKey
        self.isChange = proto.isChange
    }

    func mapToProtobuff() -> VSBitcoinOutput {
        .with {
            $0.amount = amount
            $0.address = address
            if let opReturnData {
                $0.opReturnData = opReturnData
            }
            $0.scriptPubKey = scriptPubKey
            $0.isChange = isChange
        }
    }
}

struct SignBitcoin: Codable, Hashable {
    let version: UInt32
    let locktime: UInt32
    let inputs: [BitcoinInput]
    let outputs: [BitcoinOutput]

    init(
        version: UInt32,
        locktime: UInt32,
        inputs: [BitcoinInput],
        outputs: [BitcoinOutput]
    ) {
        self.version = version
        self.locktime = locktime
        self.inputs = inputs
        self.outputs = outputs
    }

    init(proto: VSSignBitcoin) {
        self.version = proto.version
        self.locktime = proto.locktime
        self.inputs = proto.inputs.map { BitcoinInput(proto: $0) }
        self.outputs = proto.outputs.map { BitcoinOutput(proto: $0) }
    }

    func mapToProtobuff() -> VSSignBitcoin {
        .with {
            $0.version = version
            $0.locktime = locktime
            $0.inputs = inputs.map { $0.mapToProtobuff() }
            $0.outputs = outputs.map { $0.mapToProtobuff() }
        }
    }
}
