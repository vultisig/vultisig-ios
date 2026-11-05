//
//  ZcashV5Transaction.swift
//  VultisigApp
//

import Foundation
import Tss
import WalletCore

enum ZcashV5TransactionError: LocalizedError, Equatable {
    case invalidBranchId(byteCount: Int)
    case noInputs
    case nonP2PKHInput(index: Int)
    case invalidOutputAddress(String)
    case memoTooLong(byteCount: Int)
    case invalidSignature(inputIndex: Int)

    var errorDescription: String? {
        switch self {
        case .invalidBranchId(let byteCount):
            return "Zcash consensus branch id must be 4 bytes, got \(byteCount)"
        case .noInputs:
            return "Zcash transaction plan has no inputs"
        case .nonP2PKHInput(let index):
            return "Zcash input \(index) is not a transparent P2PKH output"
        case .invalidOutputAddress(let address):
            return "Zcash output address \(address) has no lock script"
        case .memoTooLong(let byteCount):
            return "Zcash OP_RETURN memo is \(byteCount) bytes, the limit is \(ZcashV5Transaction.maxMemoLength)"
        case .invalidSignature(let inputIndex):
            return "Zcash signature for input \(inputIndex) does not verify against its sighash"
        }
    }
}

/// Transparent-only Zcash v5 transaction (ZIP-225 encoding, ZIP-244 sighash and
/// txid) built from the plan in a WalletCore `BitcoinSigningInput`, in WalletCore's
/// input and output order.
struct ZcashV5Transaction {
    struct Input {
        let prevout: Data
        let amount: Int64
        let script: Data
        let sequence: UInt32
    }

    struct Output {
        let amount: Int64
        let script: Data
    }

    /// WalletCore's `MaxOpReturnLength`: longer memos produce no OP_RETURN script.
    static let maxMemoLength = 80

    let branchId: UInt32
    let lockTime: UInt32
    let inputs: [Input]
    let outputs: [Output]

    /// The per-input ZIP-244 SIGHASH_ALL digests, in input order.
    static func preImageHashes(inputData: Data) throws -> [Data] {
        try ZcashV5Transaction(signingInput: BitcoinSigningInput(serializedBytes: inputData)).sighashes
    }

    /// Verifies each input's DER signature against its sighash, then returns the
    /// signed v5 transaction and its ZIP-244 txid in display order.
    static func compile(
        inputData: Data,
        signatures: [String: TssKeysignResponse],
        publicKey: PublicKey
    ) throws -> SignedTransactionResult {
        let tx = try ZcashV5Transaction(signingInput: BitcoinSigningInput(serializedBytes: inputData))
        let signatureProvider = SignatureProvider(signatures: signatures)
        let scriptSigs = try tx.sighashes.enumerated().map { index, sighash in
            let signature = signatureProvider.getDerSignature(preHash: sighash)
            guard publicKey.verifyAsDER(signature: signature, message: sighash) else {
                throw ZcashV5TransactionError.invalidSignature(inputIndex: index)
            }
            return lengthPrefixed(signature + [sighashAll]) + lengthPrefixed(publicKey.data)
        }
        return SignedTransactionResult(
            rawTransaction: tx.serialized(scriptSigs: scriptSigs).hexString,
            transactionHash: Data(tx.txid.reversed()).hexString
        )
    }

    init(signingInput input: BitcoinSigningInput) throws {
        let plan = input.plan
        guard plan.branchID.count == 4 else {
            throw ZcashV5TransactionError.invalidBranchId(byteCount: plan.branchID.count)
        }
        guard !plan.utxos.isEmpty else {
            throw ZcashV5TransactionError.noInputs
        }
        branchId = plan.branchID.reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        lockTime = input.lockTime
        inputs = try plan.utxos.enumerated().map { index, utxo in
            guard Self.isPayToPublicKeyHash(utxo.script) else {
                throw ZcashV5TransactionError.nonP2PKHInput(index: index)
            }
            return Input(
                prevout: utxo.outPoint.hash + uint32LE(utxo.outPoint.index),
                amount: utxo.amount,
                script: utxo.script,
                sequence: utxo.outPoint.sequence
            )
        }

        var outputs = [Output(amount: plan.amount, script: try Self.lockScript(input.toAddress))]
        if plan.change > 0 {
            outputs.append(Output(amount: plan.change, script: try Self.lockScript(input.changeAddress)))
        }
        if !plan.outputOpReturn.isEmpty {
            outputs.append(Output(amount: 0, script: try Self.opReturnScript(plan.outputOpReturn)))
        }
        self.outputs = outputs
    }

    // MARK: - ZIP-244 digests

    var sighashes: [Data] {
        let header = headerDigest
        let amounts = blake2b(Personalization.amounts, Data(inputs.map { int64LE($0.amount) }.joined()))
        let scripts = blake2b(Personalization.scripts, Data(inputs.map { lengthPrefixed($0.script) }.joined()))
        let transparentPrefix = Data([sighashAll]) + prevoutsDigest + amounts + scripts + sequencesDigest + outputsDigest
        return inputs.map { input in
            let txIn = blake2b(
                Personalization.txIn,
                input.prevout + int64LE(input.amount) + lengthPrefixed(input.script) + uint32LE(input.sequence)
            )
            let transparent = blake2b(Personalization.transparent, transparentPrefix + txIn)
            return blake2b(txPersonalization, header + transparent + emptyShieldedDigests)
        }
    }

    var txid: Data {
        let transparent = blake2b(Personalization.transparent, prevoutsDigest + sequencesDigest + outputsDigest)
        return blake2b(txPersonalization, headerDigest + transparent + emptyShieldedDigests)
    }

    private var headerFields: Data {
        uint32LE(Self.versionHeader) + uint32LE(Self.versionGroupId) + uint32LE(branchId) + uint32LE(lockTime) + uint32LE(Self.expiryHeight)
    }

    private var headerDigest: Data {
        blake2b(Personalization.headers, headerFields)
    }

    private var prevoutsDigest: Data {
        blake2b(Personalization.prevouts, Data(inputs.map(\.prevout).joined()))
    }

    private var sequencesDigest: Data {
        blake2b(Personalization.sequences, Data(inputs.map { uint32LE($0.sequence) }.joined()))
    }

    private var outputsDigest: Data {
        blake2b(Personalization.outputs, Data(outputs.map(serializedOutput).joined()))
    }

    private var emptyShieldedDigests: Data {
        blake2b(Personalization.sapling, Data()) + blake2b(Personalization.orchard, Data())
    }

    private var txPersonalization: Data {
        Data("ZcashTxHash_".utf8) + uint32LE(branchId)
    }

    // MARK: - ZIP-225 encoding

    private func serialized(scriptSigs: [Data]) -> Data {
        var data = headerFields + compactSize(inputs.count)
        for (input, scriptSig) in zip(inputs, scriptSigs) {
            data += input.prevout + lengthPrefixed(scriptSig) + uint32LE(input.sequence)
        }
        data += compactSize(outputs.count) + Data(outputs.map(serializedOutput).joined())
        // nSpendsSapling, nOutputsSapling, nActionsOrchard
        return data + Data([0x00, 0x00, 0x00])
    }

    private func serializedOutput(_ output: Output) -> Data {
        int64LE(output.amount) + lengthPrefixed(output.script)
    }

    // MARK: - Scripts

    /// `OP_DUP OP_HASH160 <push 20-byte hash> OP_EQUALVERIFY OP_CHECKSIG`.
    private static func isPayToPublicKeyHash(_ script: Data) -> Bool {
        script.count == 25 && script.starts(with: [0x76, 0xa9, 0x14]) && script.suffix(2).elementsEqual([0x88, 0xac])
    }

    private static func lockScript(_ address: String) throws -> Data {
        let script = BitcoinScript.lockScriptForAddress(address: address, coin: .zcash).data
        guard !script.isEmpty else {
            throw ZcashV5TransactionError.invalidOutputAddress(address)
        }
        return script
    }

    /// `OP_RETURN <push memo>`, matching WalletCore's `Script::buildOpReturnScript`.
    private static func opReturnScript(_ memo: Data) throws -> Data {
        guard memo.count <= maxMemoLength else {
            throw ZcashV5TransactionError.memoTooLong(byteCount: memo.count)
        }
        let opReturn: UInt8 = 0x6a
        let opPushData1: UInt8 = 0x4c
        let push: [UInt8] = memo.count < opPushData1 ? [UInt8(memo.count)] : [opPushData1, UInt8(memo.count)]
        return Data([opReturn] + push) + memo
    }

    // MARK: - Constants

    private static let versionHeader: UInt32 = 0x8000_0005
    private static let versionGroupId: UInt32 = 0x26A7_270A
    private static let expiryHeight: UInt32 = 0

    private enum Personalization {
        static let headers = Data("ZTxIdHeadersHash".utf8)
        static let prevouts = Data("ZTxIdPrevoutHash".utf8)
        static let sequences = Data("ZTxIdSequencHash".utf8)
        static let outputs = Data("ZTxIdOutputsHash".utf8)
        static let amounts = Data("ZTxTrAmountsHash".utf8)
        static let scripts = Data("ZTxTrScriptsHash".utf8)
        static let txIn = Data("Zcash___TxInHash".utf8)
        static let transparent = Data("ZTxIdTranspaHash".utf8)
        static let sapling = Data("ZTxIdSaplingHash".utf8)
        static let orchard = Data("ZTxIdOrchardHash".utf8)
    }
}

// MARK: - Byte helpers

private let sighashAll: UInt8 = 0x01

private func blake2b(_ personal: Data, _ data: Data) -> Data {
    Hash.blake2bPersonal(data: data, personal: personal, outlen: 32)
}

private func uint32LE(_ value: UInt32) -> Data {
    withUnsafeBytes(of: value.littleEndian) { Data($0) }
}

private func int64LE(_ value: Int64) -> Data {
    withUnsafeBytes(of: value.littleEndian) { Data($0) }
}

/// Bitcoin CompactSize length prefix.
private func compactSize(_ count: Int) -> Data {
    switch count {
    case ..<0xFD:
        return Data([UInt8(count)])
    case ...0xFFFF:
        return Data([0xFD]) + withUnsafeBytes(of: UInt16(count).littleEndian) { Data($0) }
    default:
        return Data([0xFE]) + uint32LE(UInt32(count))
    }
}

private func lengthPrefixed(_ bytes: Data) -> Data {
    compactSize(bytes.count) + bytes
}
