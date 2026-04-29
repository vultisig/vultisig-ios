//
//  SignBitcoin.swift
//  VultisigApp
//
//  Swift wrapper for the `SignBitcoin` proto OneOf case (added to
//  `commondata` in `feat/sign-bitcoin`). Decomposes a BIP-174 PSBT into
//  verifiable fields so co-signing devices can display tx details and
//  compute exact sighashes without receiving an opaque blob.
//
//  Adoption is mapping-only — the iOS UI does not yet render or sign
//  these payloads. Future work will add a verification view and a
//  Bitcoin-specific keysign path.
//

import Foundation
import VultisigCommonData

struct SignBitcoin: Codable, Hashable {
    /// Transaction version (typically 1 or 2).
    let version: UInt32
    /// Transaction locktime.
    let locktime: UInt32
    /// All inputs in exact PSBT order.
    let inputs: [BitcoinInput]
    /// All outputs in exact PSBT order.
    let outputs: [BitcoinOutput]

    init(version: UInt32, locktime: UInt32, inputs: [BitcoinInput], outputs: [BitcoinOutput]) {
        self.version = version
        self.locktime = locktime
        self.inputs = inputs
        self.outputs = outputs
    }

    init(proto: VSSignBitcoin) {
        self.version = proto.version
        self.locktime = proto.locktime
        self.inputs = proto.inputs.map(BitcoinInput.init(proto:))
        self.outputs = proto.outputs.map(BitcoinOutput.init(proto:))
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

struct BitcoinInput: Codable, Hashable {
    /// Previous txid (hex, big-endian).
    let hash: String
    /// Previous output index (vout).
    let index: UInt32
    /// Satoshis (from witness UTXO).
    let amount: Int64
    /// Hex scriptPubKey of the UTXO being spent.
    let scriptPubKey: String
    /// `"p2wpkh"`, `"p2pkh"`, `"p2tr"`, `"p2sh-p2wpkh"`.
    let scriptType: String
    /// BIP-143/341 sighash flag; `nil` ⇒ SIGHASH_ALL (1).
    let sighashType: UInt32?
    /// Whether this device signs this input.
    let isOurs: Bool
    /// For P2SH-P2WPKH: hex redeem script.
    let redeemScript: String?
    /// nSequence; `nil` ⇒ `0xFFFFFFFF`.
    let sequence: UInt32?

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
            if let sighashType { $0.sighashType = sighashType }
            $0.isOurs = isOurs
            if let redeemScript { $0.redeemScript = redeemScript }
            if let sequence { $0.sequence = sequence }
        }
    }
}

struct BitcoinOutput: Codable, Hashable {
    /// Satoshis.
    let amount: Int64
    /// Decoded address (empty for OP_RETURN).
    let address: String
    /// Hex data if OP_RETURN.
    let opReturnData: String?
    /// Hex output scriptPubKey.
    let scriptPubKey: String
    /// Whether output is change back to sender.
    let isChange: Bool

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
            if let opReturnData { $0.opReturnData = opReturnData }
            $0.scriptPubKey = scriptPubKey
            $0.isChange = isChange
        }
    }
}
