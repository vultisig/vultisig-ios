//
//  bitcoin.swift
//  VoltixApp
//

import Foundation
import Tss
import WalletCore

struct UtxoInfo: Codable, Hashable {
    let hash: String
    let amount: Int64
    let index: UInt32
}

enum BitcoinHelper {
    static func validateAddress(_ address: String) -> Bool {
        return CoinType.bitcoin.validate(address: address)
    }
    
    static func getBitcoin(hexPubKey: String, hexChainCode: String) -> Result<Coin, Error> {
        return getAddressFromPubKey(hexPubKey: hexPubKey, hexChainCode: hexChainCode)
            .map { addr in
                Coin(chain: Chain.Bitcoin, ticker: "BTC", logo: "", address: addr)
            }
    }
    
    static func getBitcoinPubKey(hexPubKey: String, hexChainCode: String) -> String {
        return PublicKeyHelper.getDerivedPubKey(hexPubKey: hexPubKey, hexChainCode: hexChainCode, derivePath: CoinType.bitcoin.derivationPath())
    }
    
    static func getAddressFromPubKey(hexPubKey: String, hexChainCode: String) -> Result<String, Error> {
        let derivedPubKey = PublicKeyHelper.getDerivedPubKey(hexPubKey: hexPubKey, hexChainCode: hexChainCode, derivePath: CoinType.bitcoin.derivationPath())
        guard let pubkeyData = Data(hexString: derivedPubKey),
              let publicKey = PublicKey(data: pubkeyData, type: .secp256k1)
        else {
            return .failure(HelperError.runtimeError("public key \(derivedPubKey) is invalid"))
        }
        
        return .success(CoinType.bitcoin.deriveAddressFromPublicKey(publicKey: publicKey))
    }
    
    // before keysign , we need to get the preSignedImageHash , so it can be signed with TSS
    static func getPreSignedImageHash(keysignPayload: KeysignPayload) -> Result<[String], Error> {
        let result = getBitcoinPreSigningInputData(keysignPayload: keysignPayload)
        switch result {
            case .success(let inputData):
                do {
                    let preHashes = TransactionCompiler.preImageHashes(coinType: .bitcoin, txInputData: inputData)
                    let preSignOutputs = try BitcoinPreSigningOutput(serializedData: preHashes)
                    return .success(preSignOutputs.hashPublicKeys.map { $0.dataHash.hexString })
                } catch {
                    return .failure(HelperError.runtimeError("fail to get presigned image hashes,error:\(error.localizedDescription)"))
                }
            case .failure(let err):
                return .failure(err)
        }
    }
    
    static func getBitcoinSigningInput(keysignPayload: KeysignPayload) -> Result<BitcoinSigningInput, Error> {
        guard keysignPayload.coin.chain.name == "BTC" else {
            return .failure(HelperError.runtimeError("coin is not BTC"))
        }
        guard case .Bitcoin(let byteFee) = keysignPayload.chainSpecific else {
            return .failure(HelperError.runtimeError("fail to get Bitcoin chain specific"))
        }
        
        let coin = CoinType.bitcoin
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
            let lockScript = BitcoinScript.lockScriptForAddress(address: keysignPayload.coin.address, coin: .bitcoin)
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
    
    static func getBitcoinPreSigningInputData(keysignPayload: KeysignPayload) -> Result<Data, Error> {
        let result = getBitcoinSigningInput(keysignPayload: keysignPayload)
        switch result {
            case .success(var input):
                let plan: BitcoinTransactionPlan = AnySigner.plan(input: input, coin: .bitcoin)
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
    
    static func getBitcoinTransactionPlan(keysignPayload: KeysignPayload) -> Result<BitcoinTransactionPlan, Error> {
        let result = getBitcoinSigningInput(keysignPayload: keysignPayload)
        switch result {
            case .success(let input):
                let plan: BitcoinTransactionPlan = AnySigner.plan(input: input, coin: .bitcoin)
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
        let bitcoinPubKey = BitcoinHelper.getBitcoinPubKey(hexPubKey: vaultHexPubKey, hexChainCode: vaultHexChainCode)
        guard let pubkeyData = Data(hexString: bitcoinPubKey),
              let publicKey = PublicKey(data: pubkeyData, type: .secp256k1)
        else {
            return .failure(HelperError.runtimeError("public key \(bitcoinPubKey) is invalid"))
        }
        
        let result = getBitcoinPreSigningInputData(keysignPayload: keysignPayload)
        switch result {
            case .success(let preSignInputData):
                do {
                    let preHashes = TransactionCompiler.preImageHashes(coinType: .bitcoin, txInputData: preSignInputData)
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
                    let compileWithSignatures = TransactionCompiler.compileWithSignatures(coinType: .bitcoin, txInputData: preSignInputData, signatures: allSignatures, publicKeys: publicKeys)
                    let output = try BitcoinSigningOutput(serializedData: compileWithSignatures)
                    return .success(output.encoded.hexString)
                } catch {
                    return .failure(HelperError.runtimeError("fail to construct raw transaction,error: \(error.localizedDescription)"))
                }
                
            case .failure(let error):
                return .failure(error)
        }
    }
}
