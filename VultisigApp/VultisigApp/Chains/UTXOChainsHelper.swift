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
}

class UTXOChainsHelper {
    let coin: CoinType
    let vaultHexPublicKey: String
    let vaultHexChainCode: String
    init(coin: CoinType, vaultHexPublicKey: String, vaultHexChainCode: String) {
        self.coin = coin
        self.vaultHexPublicKey = vaultHexPublicKey
        self.vaultHexChainCode = vaultHexChainCode
    }
    
    static func getHelper(vault: Vault, coin: Coin) -> UTXOChainsHelper? {
        switch coin.chainType {
        case .UTXO:
            guard let coinType = CoinType.from(string: coin.chain.name) else {
                return nil
            }
            return UTXOChainsHelper(coin: coinType, vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode)
        default:
            return nil
        }
    }
    
    func getDerivedPubKey() -> String {
        return PublicKeyHelper.getDerivedPubKey(hexPubKey: vaultHexPublicKey, hexChainCode: vaultHexChainCode, derivePath: coin.derivationPath())
    }
    
    // before keysign , we need to get the preSignedImageHash , so it can be signed with TSS
    func getPreSignedImageHash(keysignPayload: KeysignPayload) throws -> [String] {
        let inputData = try getBitcoinPreSigningInputData(keysignPayload: keysignPayload)
        let preHashes = TransactionCompiler.preImageHashes(coinType: coin, txInputData: inputData)
        let preSignOutputs = try BitcoinPreSigningOutput(serializedBytes: preHashes)
        if !preSignOutputs.errorMessage.isEmpty {
            throw HelperError.runtimeError(preSignOutputs.errorMessage)
        }
        return preSignOutputs.hashPublicKeys.map { $0.dataHash.hexString }.sorted()
    }
    
    func getSigningInputData(keysignPayload: KeysignPayload, signingInput: BitcoinSigningInput) throws -> Data {
        guard case .UTXO(let byteFee, let sendMaxAmount) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get UTXO chain specific byte fee")
        }
        var input = signingInput
        input.byteFee = Int64(byteFee)
        input.hashType = BitcoinScript.hashTypeForCoin(coinType: coin)
        input.useMaxAmount = sendMaxAmount
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
            case CoinType.bitcoinCash, CoinType.dogecoin, CoinType.dash:
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
        
        let plan: BitcoinTransactionPlan = AnySigner.plan(input: input, coin: coin)
        input.plan = plan
        return try input.serializedData()
    }
    
    func getBitcoinSigningInput(keysignPayload: KeysignPayload) throws -> BitcoinSigningInput {
        guard case .UTXO(let byteFee, let sendMaxAmount) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get UTXO chain specific byte fee")
        }
        
        // Prevent from accedentally sending all balance
        var safeGuardMaxAmount = false
        if let rawBalance = Int64(keysignPayload.coin.rawBalance),
           sendMaxAmount,
           rawBalance > 0,
           rawBalance == Int64(keysignPayload.toAmount) {
            safeGuardMaxAmount = true
        }
        
        var input = BitcoinSigningInput.with {
            $0.hashType = BitcoinScript.hashTypeForCoin(coinType: self.coin)
            $0.amount = Int64(keysignPayload.toAmount)
            $0.useMaxAmount = safeGuardMaxAmount
            $0.toAddress = keysignPayload.toAddress
            $0.changeAddress = keysignPayload.coin.address
            $0.byteFee = Int64(byteFee)
            $0.coinType = coin.rawValue
            if let memoData = keysignPayload.memo?.data(using: .utf8) {
                $0.outputOpReturn = memoData
            }
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
            case CoinType.bitcoinCash, CoinType.dogecoin, CoinType.dash:
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
        let plan: BitcoinTransactionPlan = AnySigner.plan(input: input, coin: coin)
        input.plan = plan
        let inputData = try input.serializedData()
        return inputData
    }
    
    func getBitcoinTransactionPlan(keysignPayload: KeysignPayload) throws -> BitcoinTransactionPlan {
        let input = try getBitcoinSigningInput(keysignPayload: keysignPayload)
        let plan: BitcoinTransactionPlan = AnySigner.plan(input: input, coin: coin)
        return plan
    }
    
    func getSignedTransaction(keysignPayload: KeysignPayload, signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult {
        let inputData = try getBitcoinPreSigningInputData(keysignPayload: keysignPayload)
        return try getSignedTransaction(inputData: inputData, signatures: signatures)
    }
    
    func getSignedTransaction(inputData: Data, signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult {
        let bitcoinPubKey = getDerivedPubKey()
        guard let pubkeyData = Data(hexString: bitcoinPubKey),
              let publicKey = PublicKey(data: pubkeyData, type: .secp256k1)
        else {
            throw HelperError.runtimeError("public key \(bitcoinPubKey) is invalid")
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
}
