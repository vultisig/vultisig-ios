//
//  bitcoincash.swift
//  VoltixApp
//

import Foundation
import Tss
import WalletCore

enum BitcoinCashHelper {
    static func validateAddress(_ address: String) -> Bool {
        return CoinType.bitcoinCash.validate(address: address)
    }
    
    static func getBitcoinCash(hexPubKey: String, hexChainCode: String) -> Result<Coin, Error> {
        return getAddressFromPubKey(hexPubKey: hexPubKey, hexChainCode: hexChainCode)
            .map { addr in
                Coin(chain: Chain.BitcoinCash,
                     ticker: "BCH",
                     logo: "",
                     address: addr,
                     hexPublicKey: getBitcoinCashPubKey(hexPubKey: hexPubKey, hexChainCode: hexChainCode),
                     feeUnit: "SATS",
                     contractAddress: nil)
            }
    }
    
    static func getBitcoinCashPubKey(hexPubKey: String, hexChainCode: String) -> String {
        return PublicKeyHelper.getDerivedPubKey(hexPubKey: hexPubKey, hexChainCode: hexChainCode, derivePath: CoinType.bitcoinCash.derivationPath())
    }

    static func getAddressFromPubKey(hexPubKey: String, hexChainCode: String) -> Result<String, Error> {
        let derivedPubKey = PublicKeyHelper.getDerivedPubKey(hexPubKey: hexPubKey, hexChainCode: hexChainCode, derivePath: CoinType.bitcoinCash.derivationPath())
        guard let pubkeyData = Data(hexString: derivedPubKey),
              let publicKey = PublicKey(data: pubkeyData, type: .secp256k1)
        else {
            return .failure(HelperError.runtimeError("public key \(derivedPubKey) is invalid"))
        }
        
        return .success(CoinType.bitcoinCash.deriveAddressFromPublicKey(publicKey: publicKey))
    }
    
    // before keysign , we need to get the preSignedImageHash , so it can be signed with TSS
    static func getPreSignedImageHash(keysignPayload: KeysignPayload) -> Result<[String], Error> {
        let result = getPreSigningInputData(keysignPayload: keysignPayload)
        switch result {
        case .success(let inputData):
            do {
                let preHashes = TransactionCompiler.preImageHashes(coinType: .bitcoinCash, txInputData: inputData)
                let preSignOutputs = try BitcoinPreSigningOutput(serializedData: preHashes)
                return .success(preSignOutputs.hashPublicKeys.map { $0.dataHash.hexString })
            } catch {
                return .failure(HelperError.runtimeError("fail to get presigned image hashes,error:\(error.localizedDescription)"))
            }
        case .failure(let err):
            return .failure(err)
        }
    }
    
    static func getSigningInputData(keysignPayload: KeysignPayload, signingInput: BitcoinSigningInput) -> Result<Data, Error> {
        guard keysignPayload.coin.chain.ticker == "BCH" else {
            return .failure(HelperError.runtimeError("coin is not BCH"))
        }
        guard case .Bitcoin(let byteFee) = keysignPayload.chainSpecific else {
            return .failure(HelperError.runtimeError("fail to get Bitcoin chain specific"))
        }
        var input = signingInput
        input.byteFee = byteFee
        input.hashType = BitcoinSigHashType.all.rawValue
        input.useMaxAmount = false
        
        for inputUtxo in keysignPayload.utxos {
            let lockScript = BitcoinScript.lockScriptForAddress(address: keysignPayload.coin.address, coin: .bitcoinCash)
            let keyHash = lockScript.matchPayToWitnessPublicKeyHash()
            guard let keyHash else {
                return .failure(HelperError.runtimeError("fail to get key hash from lock script"))
            }
            let redeemScript = BitcoinScript.buildPayToWitnessPubkeyHash(hash: keyHash)
            input.scripts[keyHash.hexString] = redeemScript.data
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
        do {
            let plan: BitcoinTransactionPlan = AnySigner.plan(input: input, coin: .bitcoinCash)
            input.plan = plan
            let inputData = try input.serializedData()
            return .success(inputData)
        } catch {
            return .failure(HelperError.runtimeError("fail to get preSignedImageHash,error:\(error.localizedDescription)"))
        }
    }
    
    static func getSigningInput(keysignPayload: KeysignPayload) -> Result<BitcoinSigningInput, Error> {
        guard keysignPayload.coin.chain.ticker == "BCH" else {
            return .failure(HelperError.runtimeError("coin is not BCH"))
        }
        guard case .Bitcoin(let byteFee) = keysignPayload.chainSpecific else {
            return .failure(HelperError.runtimeError("fail to get Bitcoin chain specific"))
        }
        
        let coin = CoinType.bitcoinCash
        var input = BitcoinSigningInput.with {
            $0.hashType = BitcoinSigHashType.all.rawValue
            $0.amount = keysignPayload.toAmount
            $0.useMaxAmount = false
            $0.toAddress = keysignPayload.toAddress
            $0.changeAddress = keysignPayload.coin.address
            $0.byteFee = byteFee
            $0.coinType = coin.rawValue
            if let memoData = keysignPayload.memo?.data(using: .utf8) {
                $0.outputOpReturn = memoData
            }
        }
        for inputUtxo in keysignPayload.utxos {
            let lockScript = BitcoinScript.lockScriptForAddress(address: keysignPayload.coin.address, coin: .bitcoinCash)
            let keyHash = lockScript.matchPayToWitnessPublicKeyHash()
            guard let keyHash else {
                return .failure(HelperError.runtimeError("fail to get key hash from lock script"))
            }
            let redeemScript = BitcoinScript.buildPayToWitnessPubkeyHash(hash: keyHash)
            input.scripts[keyHash.hexString] = redeemScript.data
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
        
        return .success(input)
    }
    
    static func getPreSigningInputData(keysignPayload: KeysignPayload) -> Result<Data, Error> {
        let result = getSigningInput(keysignPayload: keysignPayload)
        switch result {
        case .success(var input):
            let plan: BitcoinTransactionPlan = AnySigner.plan(input: input, coin: .bitcoinCash)
            input.plan = plan
            do {
                let inputData = try input.serializedData()
                return .success(inputData)
            } catch {
                print("fail to serialize input data,err:\(error.localizedDescription)")
                return .failure(error)
            }
        case .failure(let err):
            return .failure(err)
        }
    }
    
    static func getTransactionPlan(keysignPayload: KeysignPayload) -> Result<BitcoinTransactionPlan, Error> {
        let result = getSigningInput(keysignPayload: keysignPayload)
        switch result {
        case .success(let input):
            let plan: BitcoinTransactionPlan = AnySigner.plan(input: input, coin: .bitcoinCash)
            return .success(plan)
        case .failure(let err):
            return .failure(err)
        }
    }
    
    static func getSignedTransaction(
        vaultHexPubKey: String,
        vaultHexChainCode: String,
        keysignPayload: KeysignPayload,
        signatures: [String: TssKeysignResponse]) -> Result<String, Error>
    {
        let result = getPreSigningInputData(keysignPayload: keysignPayload)
        switch result {
        case .success(let inputData):
            return getSignedTransaction(vaultHexPubKey: vaultHexPubKey, vaultHexChainCode: vaultHexChainCode, inputData: inputData, signatures: signatures)
            
        case .failure(let err):
            return .failure(err)
        }
    }
    
    static func getSignedTransaction(
        vaultHexPubKey: String,
        vaultHexChainCode: String,
        inputData: Data,
        signatures: [String: TssKeysignResponse]) -> Result<String, Error>
    {
        let bitcoinPubKey = BitcoinCashHelper.getBitcoinCashPubKey(hexPubKey: vaultHexPubKey, hexChainCode: vaultHexChainCode)
        guard let pubkeyData = Data(hexString: bitcoinPubKey),
              let publicKey = PublicKey(data: pubkeyData, type: .secp256k1)
        else {
            return .failure(HelperError.runtimeError("public key \(bitcoinPubKey) is invalid"))
        }
        
        do {
            let preHashes = TransactionCompiler.preImageHashes(coinType: .bitcoinCash, txInputData: inputData)
            let preSignOutputs = try BitcoinPreSigningOutput(serializedData: preHashes)
            let allSignatures = DataVector()
            let publicKeys = DataVector()
            let signatureProvider = SignatureProvider(signatures: signatures)
            for h in preSignOutputs.hashPublicKeys {
                let preImageHash = h.dataHash
                let signature = signatureProvider.getDerSignature(preHash: preImageHash)
                guard publicKey.verifyAsDER(signature: signature, message: preImageHash) else {
                    return .failure(HelperError.runtimeError("fail to verify signature"))
                }
                allSignatures.add(data: signature)
                publicKeys.add(data: pubkeyData)
            }
            let compileWithSignatures = TransactionCompiler.compileWithSignatures(coinType: .bitcoinCash, txInputData: inputData, signatures: allSignatures, publicKeys: publicKeys)
            let output = try BitcoinSigningOutput(serializedData: compileWithSignatures)
            return .success(output.encoded.hexString)
        } catch {
            return .failure(HelperError.runtimeError("fail to construct raw transaction,error: \(error.localizedDescription)"))
        }
    }
}
