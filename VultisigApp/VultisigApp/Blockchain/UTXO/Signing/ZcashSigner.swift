//
//  ZcashSigner.swift
//  VultisigApp
//

import Foundation
import Tss
import WalletCore

enum ZcashSignerError: LocalizedError, Equatable {
    case invalidBranchId(byteCount: Int)
    case noInputs
    case memoTooLong(byteCount: Int)
    case walletCore(String)
    case invalidSignature(inputIndex: Int)

    var errorDescription: String? {
        switch self {
        case .invalidBranchId(let byteCount):
            return "Zcash consensus branch id must be 4 bytes, got \(byteCount)"
        case .noInputs:
            return "Zcash transaction plan has no inputs"
        case .memoTooLong(let byteCount):
            return "Zcash OP_RETURN memo is \(byteCount) bytes, the limit is \(ZcashSigner.maxMemoLength)"
        case .walletCore(let message):
            return "WalletCore Zcash signing failed: \(message)"
        case .invalidSignature(let inputIndex):
            return "Zcash signature for input \(inputIndex) does not verify against its sighash"
        }
    }
}

/// Zcash v5 (ZIP-225 / ZIP-244) signing through WalletCore's signing V2 builder.
/// The legacy `TransactionCompiler` path only emits v4, which NU7 makes invalid.
/// WalletCore's planner still runs on the legacy input; its plan is replayed here
/// as explicit P2PKH inputs of `publicKey` and outputs (to → change iff > 0 → OP_RETURN iff memo).
enum ZcashSigner {
    /// WalletCore's `MaxOpReturnLength`: longer memos produce no OP_RETURN script.
    static let maxMemoLength = 80

    private static let sighashAll = UInt32(BitcoinSigHashType.all.rawValue)

    /// The per-input ZIP-244 SIGHASH_ALL digests, in input order.
    static func preImageHashes(inputData: Data, publicKey: Data) throws -> [Data] {
        let v2 = try signingInputV2(from: inputData, publicKey: publicKey)
        let output = try BitcoinPreSigningOutput(
            serializedBytes: TransactionCompiler.preImageHashes(coinType: .zcash, txInputData: v2)
        ).preSigningResultV2
        guard output.error == .ok else {
            throw ZcashSignerError.walletCore(output.errorMessage)
        }
        return output.sighashes.map(\.sighash)
    }

    /// Verifies each input's signature against its sighash, then returns the
    /// signed v5 transaction and its ZIP-244 txid in display order.
    static func compile(
        inputData: Data,
        signatures: [String: TssKeysignResponse],
        publicKey: PublicKey
    ) throws -> SignedTransactionResult {
        let v2 = try signingInputV2(from: inputData, publicKey: publicKey.data)
        let provider = SignatureProvider(signatures: signatures)
        let derSignatures = DataVector()
        let publicKeys = DataVector()
        for (index, sighash) in try preImageHashes(inputData: inputData, publicKey: publicKey.data).enumerated() {
            guard publicKey.verifyAsDER(signature: provider.getDerSignature(preHash: sighash), message: sighash) else {
                throw ZcashSignerError.invalidSignature(inputIndex: index)
            }
            derSignatures.add(data: provider.getDerSignature(preHash: sighash))
            publicKeys.add(data: publicKey.data)
        }
        // ponytail: WalletCore 4.9.3's Zcash entry compiles V2 input by signing (needs a private key) and
        // drops the signatures; the Bitcoin entry forwards `signingV2` to the same Rust compiler using the
        // input's own coin type. Switch to `.zcash` once upstream fixes Zcash::Entry::compile.
        let output = try BitcoinSigningOutput(
            serializedBytes: TransactionCompiler.compileWithSignatures(
                coinType: .bitcoin, txInputData: v2, signatures: derSignatures, publicKeys: publicKeys
            )
        ).signingResultV2
        guard output.error == .ok else {
            throw ZcashSignerError.walletCore(output.errorMessage)
        }
        return SignedTransactionResult(rawTransaction: output.encoded.hexString, transactionHash: output.txid.hexString)
    }

    /// Serialized `BitcoinSigningInput` (`signingV2`) replaying the plan of a legacy `BitcoinSigningInput`.
    static func signingInputV2(from inputData: Data, publicKey: Data) throws -> Data {
        let input = try BitcoinSigningInput(serializedBytes: inputData)
        let plan = input.plan
        guard plan.branchID.count == 4 else {
            throw ZcashSignerError.invalidBranchId(byteCount: plan.branchID.count)
        }
        guard !plan.utxos.isEmpty else {
            throw ZcashSignerError.noInputs
        }
        guard plan.outputOpReturn.count <= maxMemoLength else {
            throw ZcashSignerError.memoTooLong(byteCount: plan.outputOpReturn.count)
        }

        var outputs = [BitcoinV2Output.with {
            $0.value = plan.amount
            $0.toAddress = input.toAddress
        }]
        if plan.change > 0 {
            outputs.append(BitcoinV2Output.with {
                $0.value = plan.change
                $0.toAddress = input.changeAddress
            })
        }
        if !plan.outputOpReturn.isEmpty {
            outputs.append(BitcoinV2Output.with {
                $0.value = 0
                $0.builder.opReturn = plan.outputOpReturn
            })
        }

        let signingV2 = BitcoinV2SigningInput.with {
            $0.publicKeys = [publicKey]
            $0.builder = BitcoinV2TransactionBuilder.with {
                $0.version = .useDefault
                $0.lockTime = input.lockTime
                $0.inputs = plan.utxos.map { utxo in
                    BitcoinV2Input.with {
                        $0.outPoint = UtxoOutPoint.with {
                            $0.hash = utxo.outPoint.hash
                            $0.vout = utxo.outPoint.index
                        }
                        $0.value = utxo.amount
                        $0.sighashType = sighashAll
                        $0.sequence.sequence = utxo.outPoint.sequence
                        $0.scriptBuilder.p2Pkh.pubkey = publicKey
                    }
                }
                $0.outputs = outputs
                $0.inputSelector = .useAll
                $0.fixedDustThreshold = 0
                $0.zcashExtraData = ZcashTransactionBuilderExtraData.with {
                    $0.branchID = plan.branchID
                    $0.txVersion = .v5
                }
            }
            $0.chainInfo = BitcoinV2ChainInfo.with {
                $0.p2PkhPrefix = 184
                $0.p2ShPrefix = 189
            }
        }
        return try BitcoinSigningInput.with {
            $0.coinType = CoinType.zcash.rawValue
            $0.signingV2 = signingV2
        }.serializedData()
    }
}
