//
//  SignBitcoin.swift
//  VultisigApp
//
//  Structured PSBT representation for Bitcoin dApp co-signing.
//  Mirrors the `SignBitcoin` proto from commondata so co-signing devices can
//  display verifiable transaction details and recompute exact BIP-143 sighashes
//  without trusting an opaque base64 PSBT blob.
//

import Foundation
import VultisigCommonData

struct BitcoinInput: Codable, Hashable {
    /// Previous txid (hex, big-endian display order)
    let hash: String
    /// Previous output index (vout)
    let index: UInt32
    /// Satoshis (from witness UTXO)
    let amount: Int64
    /// Hex scriptPubKey of the UTXO being spent
    let scriptPubKey: String
    /// "p2wpkh", "p2pkh", "p2tr", "p2sh-p2wpkh"
    let scriptType: String
    /// BIP-143/341 sighash flag; 0 means SIGHASH_ALL (1) by convention
    let sighashType: UInt32
    /// Whether this device signs this input
    let isOurs: Bool
    /// For P2SH-P2WPKH: hex redeem script
    let redeemScript: String?
    /// nSequence
    let sequence: UInt32

    init(
        hash: String,
        index: UInt32,
        amount: Int64,
        scriptPubKey: String,
        scriptType: String,
        sighashType: UInt32,
        isOurs: Bool,
        redeemScript: String?,
        sequence: UInt32
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
        self.sighashType = proto.hasSighashType ? proto.sighashType : 0
        self.isOurs = proto.isOurs
        self.redeemScript = proto.hasRedeemScript ? proto.redeemScript : nil
        self.sequence = proto.hasSequence ? proto.sequence : 0xFFFFFFFF
    }

    func mapToProtobuff() -> VSBitcoinInput {
        .with {
            $0.hash = self.hash
            $0.index = self.index
            $0.amount = self.amount
            $0.scriptPubKey = self.scriptPubKey
            $0.scriptType = self.scriptType
            if self.sighashType != 0 {
                $0.sighashType = self.sighashType
            }
            $0.isOurs = self.isOurs
            if let redeemScript = self.redeemScript {
                $0.redeemScript = redeemScript
            }
            $0.sequence = self.sequence
        }
    }

    /// Effective sighash flag (treats 0 as SIGHASH_ALL per proto convention).
    var effectiveSighashType: UInt32 {
        sighashType == 0 ? 1 : sighashType
    }
}

struct BitcoinOutput: Codable, Hashable {
    /// Satoshis
    let amount: Int64
    /// Decoded address (empty for OP_RETURN)
    let address: String
    /// Hex data if OP_RETURN
    let opReturnData: String?
    /// Hex output scriptPubKey
    let scriptPubKey: String
    /// Whether output is change back to sender
    let isChange: Bool

    init(
        amount: Int64,
        address: String,
        opReturnData: String?,
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
            $0.amount = self.amount
            $0.address = self.address
            if let opReturnData = self.opReturnData {
                $0.opReturnData = opReturnData
            }
            $0.scriptPubKey = self.scriptPubKey
            $0.isChange = self.isChange
        }
    }
}

struct SignBitcoin: Codable, Hashable {
    /// Transaction version (typically 1 or 2)
    let version: UInt32
    /// Transaction locktime
    let locktime: UInt32
    /// All inputs in exact PSBT order
    let inputs: [BitcoinInput]
    /// All outputs in exact PSBT order
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
            $0.version = self.version
            $0.locktime = self.locktime
            $0.inputs = self.inputs.map { $0.mapToProtobuff() }
            $0.outputs = self.outputs.map { $0.mapToProtobuff() }
        }
    }
}
