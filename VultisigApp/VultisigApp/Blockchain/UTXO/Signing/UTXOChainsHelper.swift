//
//  UTXOChains.swift
//  VultisigApp
//

import Foundation
import Tss
import WalletCore

struct UtxoInfo: Codable, Hashable {
    let hash: String
    let amount: Int64
    let index: UInt32
    /// Cardano-only: native assets carried by this UTxO. Empty for non-Cardano
    /// UTxOs. The initiator fetches these from Koios when building the keysign
    /// payload so both MPC peers read identical inputs off the wire.
    var cardanoTokens: [CardanoUtxoAsset] = []
}

class UTXOChainsHelper {
    let coin: CoinType

    init(coin: CoinType) {
        self.coin = coin
    }

    /// Live ZIP-243 branch id WalletCore reads off the plan during preimage
    /// construction. Resolved at send time and carried on the payload's UTXO
    /// specific — the initiator stamps it (BlockChainService), the co-signer
    /// re-resolves the same network-global value (JoinKeysignViewModel). There
    /// is no compiled-in fallback: signing with a stale branch id produces a tx
    /// the network rejects, so refuse to sign when it could not be resolved.
    private func zcashBranchID(keysignPayload: KeysignPayload) throws -> Data {
        guard let branchId = keysignPayload.chainSpecific.zcashBranchId,
              !branchId.isEmpty,
              let branchData = Data(hexString: branchId) else {
            throw HelperError.runtimeError("Zcash ZIP-243 consensus branch id is unavailable; cannot sign the ZEC transaction without the live branch id")
        }
        return branchData
    }

    static func getHelper(coin: Coin) -> UTXOChainsHelper? {
        switch coin.chainType {
        case .UTXO:
            guard let coinType = CoinType.from(string: coin.chain.name) else {
                return nil
            }
            return UTXOChainsHelper(coin: coinType)
        default:
            return nil
        }
    }

    // before keysign , we need to get the preSignedImageHash , so it can be signed with TSS
    func getPreSignedImageHash(keysignPayload: KeysignPayload) throws -> [String] {
        // Structured PSBT path: bypass WalletCore's planner and compute
        // BIP-143 sighashes directly from the dApp-supplied SignBitcoin
        // fields. Mirrors the SDK port; preserves exact input ordering so
        // `compileSignedTransaction` can match signatures back to inputs.
        if let signBitcoin = keysignPayload.signBitcoin {
            return try BitcoinPsbtSigner.preSigningHashes(signBitcoin)
                .map { $0.hexString }
                .sorted()
        }
        let inputData = try getBitcoinPreSigningInputData(keysignPayload: keysignPayload)
        let preHashes = TransactionCompiler.preImageHashes(coinType: coin, txInputData: inputData)
        let preSignOutputs = try BitcoinPreSigningOutput(serializedBytes: preHashes)
        if !preSignOutputs.errorMessage.isEmpty {
            throw HelperError.runtimeError(preSignOutputs.errorMessage)
        }
        return preSignOutputs.hashPublicKeys.map { $0.dataHash.hexString }.sorted()
    }

    func getSwapPreSignedInputData(keysignPayload: KeysignPayload) throws -> BitcoinSigningInput {
        guard let swapPayload = keysignPayload.swapPayload else {
            throw HelperError.runtimeError("swap payload is nil")
        }
        let thorChainSwapPayload: THORChainSwapPayload
        switch swapPayload {
        case .thorchain(let payload), .thorchainChainnet(let payload), .thorchainStagenet(let payload):
            thorChainSwapPayload = payload
        default:
            throw HelperError.runtimeError("fail to get swap payload")
        }
        guard let memo = keysignPayload.memo else {
            throw HelperError.runtimeError("swap payload memo is nil")
        }
        guard let memoData = memo.data(using: .utf8) else {
            throw HelperError.runtimeError("fail to encode memo to utf8")
        }

        let input = BitcoinSigningInput.with {
            $0.hashType = BitcoinScript.hashTypeForCoin(coinType: self.coin)
            $0.byteFee = 1
            $0.useMaxAmount = false
            $0.amount = Int64(swapPayload.fromAmount)
            $0.coinType = self.coin.rawValue
            $0.toAddress = thorChainSwapPayload.vaultAddress
            $0.changeAddress = keysignPayload.coin.address
            $0.outputOpReturn = memoData
            $0.fixedDustThreshold = coin.getFixedDustThreshold()
        }

        return input
    }

    func getSigningInputData(keysignPayload: KeysignPayload, signingInput: BitcoinSigningInput) throws -> Data {
        guard case .UTXO(let byteFee, let sendMaxAmount, _) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get UTXO chain specific byte fee")
        }
        var input = signingInput
        input.byteFee = Int64(byteFee)
        input.hashType = BitcoinScript.hashTypeForCoin(coinType: coin)
        input.useMaxAmount = sendMaxAmount
        // Zcash enforces ZIP-317: the fee must cover the tx's logical actions,
        // not just its byte size. Enable it so the planner below computes a
        // conforming fee and the node doesn't reject the swap broadcast.
        input.zip0317 = coin == .zcash
        for inputUtxo in keysignPayload.utxos {
            let lockScript = BitcoinScript.lockScriptForAddress(address: keysignPayload.coin.address, coin: coin)

            switch coin {
            case CoinType.bitcoin, CoinType.litecoin:
                let keyHash = lockScript.matchPayToWitnessPublicKeyHash()
                guard let keyHash else {
                    throw HelperError.runtimeError("fail to get key hash from lock script")
                }
                let redeemScript = BitcoinScript.buildPayToWitnessPubkeyHash(hash: keyHash)
                input.scripts[keyHash.hexString] = redeemScript.data
            case CoinType.bitcoinCash, CoinType.dogecoin, CoinType.dash, CoinType.zcash:
                let keyHash = lockScript.matchPayToPubkeyHash()
                guard let keyHash else {
                    throw HelperError.runtimeError("fail to get key hash from lock script")
                }
                let redeemScript = BitcoinScript.buildPayToPublicKeyHash(hash: keyHash)
                input.scripts[keyHash.hexString] = redeemScript.data
            default:
                throw HelperError.runtimeError("doesn't support coin \(coin)")
            }

            let utxo = BitcoinUnspentTransaction.with {
                $0.outPoint = BitcoinOutPoint.with {
                    // the network byte order need to be reversed
                    $0.hash = Data.reverse(hexString: inputUtxo.hash)
                    $0.index = inputUtxo.index
                    $0.sequence = UInt32.max
                }
                $0.amount = inputUtxo.amount
                $0.script = lockScript.data
            }
            input.utxo.append(utxo)
        }

        var plan: BitcoinTransactionPlan = AnySigner.plan(input: input, coin: coin)

        if coin == .zcash {
            plan.branchID = try zcashBranchID(keysignPayload: keysignPayload)
        }

        input.plan = plan
        return try input.serializedData()
    }

    func getBitcoinSigningInput(keysignPayload: KeysignPayload) throws -> BitcoinSigningInput {
        guard case .UTXO(let byteFee, let sendMaxAmount, _) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get UTXO chain specific byte fee")
        }

        var input = BitcoinSigningInput.with {
            $0.hashType = BitcoinScript.hashTypeForCoin(coinType: self.coin)
            $0.amount = Int64(keysignPayload.toAmount)
            $0.useMaxAmount = sendMaxAmount
            $0.toAddress = keysignPayload.toAddress
            $0.changeAddress = keysignPayload.coin.address
            $0.byteFee = Int64(byteFee)
            // Zcash enforces ZIP-317 fees: the fee must cover the tx's logical
            // actions, not just its byte size. Enabling this lets WalletCore's
            // planner compute a conforming fee and avoids node rejection
            // ("tx unpaid action limit exceeds limit of 0").
            $0.zip0317 = coin == .zcash
            $0.coinType = coin.rawValue
            if let memoData = keysignPayload.memo?.data(using: .utf8) {
                $0.outputOpReturn = memoData
            }
            $0.fixedDustThreshold = coin.getFixedDustThreshold()
        }
        for inputUtxo in keysignPayload.utxos {
            let lockScript = BitcoinScript.lockScriptForAddress(address: keysignPayload.coin.address, coin: coin)
            switch coin {
            case CoinType.bitcoin, CoinType.litecoin:

                let keyHash = lockScript.matchPayToWitnessPublicKeyHash()
                guard let keyHash else {
                    throw HelperError.runtimeError("fail to get key hash from lock script")
                }
                let redeemScript = BitcoinScript.buildPayToWitnessPubkeyHash(hash: keyHash)
                input.scripts[keyHash.hexString] = redeemScript.data
            case CoinType.bitcoinCash, CoinType.dogecoin, CoinType.dash, CoinType.zcash:
                let keyHash = lockScript.matchPayToPubkeyHash()
                guard let keyHash else {
                    throw HelperError.runtimeError("fail to get key hash from lock script")
                }
                let redeemScript = BitcoinScript.buildPayToPublicKeyHash(hash: keyHash)
                input.scripts[keyHash.hexString] = redeemScript.data
            default:
                throw HelperError.runtimeError("doesn't support coin \(coin)")
            }

            let utxo = BitcoinUnspentTransaction.with {
                $0.outPoint = BitcoinOutPoint.with {
                    // the network byte order need to be reversed
                    $0.hash = Data.reverse(hexString: inputUtxo.hash)
                    $0.index = inputUtxo.index
                    $0.sequence = UInt32.max
                }
                $0.amount = inputUtxo.amount
                $0.script = lockScript.data
            }
            input.utxo.append(utxo)
        }

        return input
    }

    func getBitcoinPreSigningInputData(keysignPayload: KeysignPayload) throws -> Data {
        var input = try getBitcoinSigningInput(keysignPayload: keysignPayload)
        var plan: BitcoinTransactionPlan = AnySigner.plan(input: input, coin: coin)

        // Check for transaction plan errors
        if plan.error != .ok {
            throw HelperError.runtimeError("Transaction plan error: \(plan.error)")
        }

        if coin == .zcash {
            plan.branchID = try zcashBranchID(keysignPayload: keysignPayload)
        }

        input.plan = plan
        return try input.serializedData()
    }

    func getBitcoinTransactionPlan(keysignPayload: KeysignPayload) throws -> BitcoinTransactionPlan {
        let input = try getBitcoinSigningInput(keysignPayload: keysignPayload)
        // The branch id only affects the ZIP-243 sighash digest, not the
        // planned amount/fee/change this method exposes for fee display, so it
        // is deliberately not set here (avoids forcing an RPC resolve on the
        // fee-preview path).
        let plan: BitcoinTransactionPlan = AnySigner.plan(input: input, coin: coin)
        return plan
    }

    func getSignedTransaction(keysignPayload: KeysignPayload, signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult {
        // Structured PSBT path: assemble the signed segwit tx from the
        // SignBitcoin fields + MPC signatures directly (skips WalletCore's
        // tx planner which can't represent dApp-supplied input/output sets).
        if let signBitcoin = keysignPayload.signBitcoin {
            return try BitcoinPsbtSigner.compileSignedTransaction(
                signBitcoin: signBitcoin,
                signatures: signatures,
                pubKeyHex: keysignPayload.coin.hexPublicKey
            )
        }
        let inputData = try getBitcoinPreSigningInputData(keysignPayload: keysignPayload)
        return try getSignedTransaction(coinHexPublicKey: keysignPayload.coin.hexPublicKey, inputData: inputData, signatures: signatures)
    }

    func getSignedTransaction(coinHexPublicKey: String, inputData: Data, signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult {
        guard let pubkeyData = Data(hexString: coinHexPublicKey),
              let publicKey = PublicKey(data: pubkeyData, type: .secp256k1)
        else {
            throw HelperError.runtimeError("public key \(coinHexPublicKey) is invalid")
        }

        do {
            let preHashes = TransactionCompiler.preImageHashes(coinType: coin, txInputData: inputData)
            let preSignOutputs = try BitcoinPreSigningOutput(serializedBytes: preHashes)
            let allSignatures = DataVector()
            let publicKeys = DataVector()
            let signatureProvider = SignatureProvider(signatures: signatures)
            for h in preSignOutputs.hashPublicKeys {
                let preImageHash = h.dataHash
                let signature = signatureProvider.getDerSignature(preHash: preImageHash)
                guard publicKey.verifyAsDER(signature: signature, message: preImageHash) else {
                    throw HelperError.runtimeError("fail to verify signature")
                }
                allSignatures.add(data: signature)
                publicKeys.add(data: pubkeyData)
            }
            let compileWithSignatures = TransactionCompiler.compileWithSignatures(coinType: coin, txInputData: inputData, signatures: allSignatures, publicKeys: publicKeys)
            let output = try BitcoinSigningOutput(serializedBytes: compileWithSignatures)
            let result = SignedTransactionResult(rawTransaction: output.encoded.hexString, transactionHash: output.transactionID)
            return result
        } catch {
            throw HelperError.runtimeError("fail to construct raw transaction,error: \(error.localizedDescription)")
        }
    }
    func getUnsignedTransactionHex(keysignPayload: KeysignPayload) throws -> String {
        let input = try getBitcoinSigningInput(keysignPayload: keysignPayload)
        // Placeholder tx for Blockaid analysis: only plan amount/change are read
        // below, so the ZIP-243 branch id (sighash-only) is irrelevant here.
        let plan: BitcoinTransactionPlan = AnySigner.plan(input: input, coin: coin)

        // Build raw transaction manually using plan data
        var rawTx = Data()

        // Version (4 bytes, little endian)
        rawTx.append(Data([0x02, 0x00, 0x00, 0x00])) // version 2

        // Input count (1 byte for 1 input, use VarInt if necessary)
        rawTx.append(Data([UInt8(keysignPayload.utxos.count)]))

        // For each input
        for inputUtxo in keysignPayload.utxos {
            // Previous transaction hash (32 bytes, reversed)
            let prevHash = Data.reverse(hexString: inputUtxo.hash)
            rawTx.append(prevHash)

            // Previous output index (4 bytes, little endian)
            let indexBytes = withUnsafeBytes(of: inputUtxo.index.littleEndian) { Data($0) }
            rawTx.append(indexBytes)

            // Script length (1 byte for empty script)
            rawTx.append(Data([0x00]))

            // Sequence (4 bytes)
            rawTx.append(Data([0xFF, 0xFF, 0xFF, 0xFF]))
        }

        // Output count
        var outputCount = 1 // main output
        if plan.change > 0 {
            outputCount += 1 // change output
        }
        rawTx.append(Data([UInt8(outputCount)]))

        // Main output
        let amountBytes = withUnsafeBytes(of: plan.amount.littleEndian) { Data($0) }
        rawTx.append(amountBytes)

        // Main output script (P2WPKH for bc1q...)
        if keysignPayload.toAddress.hasPrefix("bc1q") {
            // P2WPKH script: OP_0 + 20 bytes hash
            // For Blockaid analysis purposes, use standard P2WPKH script
            rawTx.append(Data([0x16])) // 22 bytes
            rawTx.append(Data([0x00, 0x14])) // OP_0 + push 20 bytes
            // Use address-derived hash for placeholder
            let addressData = keysignPayload.toAddress.data(using: .utf8) ?? Data()
            let hashData = addressData.prefix(20) + Data(repeating: 0x00, count: max(0, 20 - addressData.count))
            rawTx.append(hashData)
        } else {
            // For other address types, use standard script
            rawTx.append(Data([0x19])) // 25 bytes for P2PKH
            rawTx.append(Data([0x76, 0xa9, 0x14])) // OP_DUP OP_HASH160 OP_PUSHDATA(20)
            rawTx.append(Data(repeating: 0x00, count: 20)) // hash160 placeholder
            rawTx.append(Data([0x88, 0xac])) // OP_EQUALVERIFY OP_CHECKSIG
        }

        // Change output if necessary
        if plan.change > 0 {
            let changeBytes = withUnsafeBytes(of: plan.change.littleEndian) { Data($0) }
            rawTx.append(changeBytes)

            // Change script (same format as source address)
            rawTx.append(Data([0x16])) // 22 bytes
            rawTx.append(Data([0x00, 0x14])) // OP_0 + push 20 bytes
            rawTx.append(Data(repeating: 0x00, count: 20)) // hash placeholder
        }

        // Locktime (4 bytes)
        rawTx.append(Data([0x00, 0x00, 0x00, 0x00]))

        let transactionHex = rawTx.hexString

        if transactionHex.isEmpty {
            throw HelperError.runtimeError("Generated transaction is empty")
        }

        print("ZERO SIGNED TX: \(transactionHex)")

        return transactionHex
    }
}
