//
//  UTXOChains.swift
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
    
    func getCoin() -> Result<Coin, Error> {
        var ticker = "BTC"
        switch coin {
        case .bitcoin:
            ticker = "BTC"
        case .bitcoinCash:
            ticker = "BCH"
        case .litecoin:
            ticker = "LTC"
        case .dogecoin:
            ticker = "DOGE"
        case .dash:
            ticker = "DASH"
        default:
            return .failure(HelperError.runtimeError("doesn't support coin \(coin)"))
        }
        
        return getAddressFromPubKey()
            .flatMap { addr -> Result<Coin, Error> in
                TokensStore.createNewCoinInstance(ticker: ticker, address: addr, hexPublicKey: self.getDerivedPubKey())
            }
    }
    
    func getDerivedPubKey() -> String {
        return PublicKeyHelper.getDerivedPubKey(hexPubKey: vaultHexPublicKey, hexChainCode: vaultHexChainCode, derivePath: coin.derivationPath())
    }
    
    func getAddressFromPubKey() -> Result<String, Error> {
        let derivedPubKey = PublicKeyHelper.getDerivedPubKey(hexPubKey: vaultHexPublicKey, hexChainCode: vaultHexChainCode, derivePath: coin.derivationPath())
        guard let pubkeyData = Data(hexString: derivedPubKey),
              let publicKey = PublicKey(data: pubkeyData, type: .secp256k1)
        else {
            return .failure(HelperError.runtimeError("public key \(derivedPubKey) is invalid"))
        }
        
        return .success(coin.deriveAddressFromPublicKey(publicKey: publicKey))
    }
    
    // before keysign , we need to get the preSignedImageHash , so it can be signed with TSS
    func getPreSignedImageHash(keysignPayload: KeysignPayload) -> Result<[String], Error> {
        let result = getBitcoinPreSigningInputData(keysignPayload: keysignPayload)
        switch result {
        case .success(let inputData):
            do {
                let preHashes = TransactionCompiler.preImageHashes(coinType: coin, txInputData: inputData)
                let preSignOutputs = try BitcoinPreSigningOutput(serializedData: preHashes)
                return .success(preSignOutputs.hashPublicKeys.map { $0.dataHash.hexString })
            } catch {
                return .failure(HelperError.runtimeError("fail to get presigned image hashes,error:\(error.localizedDescription)"))
            }
        case .failure(let err):
            return .failure(err)
        }
    }
    
    func getSigningInputData(keysignPayload: KeysignPayload, signingInput: BitcoinSigningInput) -> Result<Data, Error> {
        guard case .UTXO(let byteFee) = keysignPayload.chainSpecific else {
            return .failure(HelperError.runtimeError("fail to get UTXO chain specific byte fee"))
        }
        var input = signingInput
        input.byteFee = byteFee
        input.hashType = BitcoinScript.hashTypeForCoin(coinType: coin)
        input.useMaxAmount = false
        for inputUtxo in keysignPayload.utxos {
            let lockScript = BitcoinScript.lockScriptForAddress(address: keysignPayload.coin.address, coin: coin)
            
            switch coin {
            case CoinType.bitcoin, CoinType.litecoin:
                let keyHash = lockScript.matchPayToWitnessPublicKeyHash()
                guard let keyHash else {
                    return .failure(HelperError.runtimeError("fail to get key hash from lock script"))
                }
                let redeemScript = BitcoinScript.buildPayToWitnessPubkeyHash(hash: keyHash)
                input.scripts[keyHash.hexString] = redeemScript.data
            case CoinType.bitcoinCash, CoinType.dogecoin, CoinType.dash:
                let keyHash = lockScript.matchPayToPubkeyHash()
                guard let keyHash else {
                    return .failure(HelperError.runtimeError("fail to get key hash from lock script"))
                }
                let redeemScript = BitcoinScript.buildPayToPublicKeyHash(hash: keyHash)
                input.scripts[keyHash.hexString] = redeemScript.data
            default:
                return .failure(HelperError.runtimeError("doesn't support coin \(coin)"))
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
        do {
            let plan: BitcoinTransactionPlan = AnySigner.plan(input: input, coin: coin)
            input.plan = plan
            let inputData = try input.serializedData()
            return .success(inputData)
        } catch {
            return .failure(HelperError.runtimeError("fail to get preSignedImageHash,error:\(error.localizedDescription)"))
        }
    }
    
    func getBitcoinSigningInput(keysignPayload: KeysignPayload) -> Result<BitcoinSigningInput, Error> {
        guard case .UTXO(let byteFee) = keysignPayload.chainSpecific else {
            return .failure(HelperError.runtimeError("fail to get UTXO chain specific byte fee"))
        }
        
        var input = BitcoinSigningInput.with {
            $0.hashType = BitcoinScript.hashTypeForCoin(coinType: self.coin)
            $0.amount = Int64(keysignPayload.toAmount)
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
            let lockScript = BitcoinScript.lockScriptForAddress(address: keysignPayload.coin.address, coin: coin)
            switch coin {
            case CoinType.bitcoin, CoinType.litecoin:
                
                let keyHash = lockScript.matchPayToWitnessPublicKeyHash()
                guard let keyHash else {
                    return .failure(HelperError.runtimeError("fail to get key hash from lock script"))
                }
                let redeemScript = BitcoinScript.buildPayToWitnessPubkeyHash(hash: keyHash)
                input.scripts[keyHash.hexString] = redeemScript.data
            case CoinType.bitcoinCash, CoinType.dogecoin, CoinType.dash:
                let keyHash = lockScript.matchPayToPubkeyHash()
                guard let keyHash else {
                    return .failure(HelperError.runtimeError("fail to get key hash from lock script"))
                }
                let redeemScript = BitcoinScript.buildPayToPublicKeyHash(hash: keyHash)
                input.scripts[keyHash.hexString] = redeemScript.data
            default:
                return .failure(HelperError.runtimeError("doesn't support coin \(coin)"))
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
        
        return .success(input)
    }
    
    func getBitcoinPreSigningInputData(keysignPayload: KeysignPayload) -> Result<Data, Error> {
        let result = getBitcoinSigningInput(keysignPayload: keysignPayload)
        switch result {
        case .success(var input):
            let plan: BitcoinTransactionPlan = AnySigner.plan(input: input, coin: coin)
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
    
    func getBitcoinTransactionPlan(keysignPayload: KeysignPayload) -> Result<BitcoinTransactionPlan, Error> {
        let result = getBitcoinSigningInput(keysignPayload: keysignPayload)
        switch result {
        case .success(let input):
            let plan: BitcoinTransactionPlan = AnySigner.plan(input: input, coin: coin)
            return .success(plan)
        case .failure(let err):
            return .failure(err)
        }
    }
    
    func getSignedTransaction(
        keysignPayload: KeysignPayload,
        signatures: [String: TssKeysignResponse]) -> Result<String, Error>
    {
        let result = getBitcoinPreSigningInputData(keysignPayload: keysignPayload)
        switch result {
        case .success(let inputData):
            return getSignedTransaction(inputData: inputData,
                                        signatures: signatures)
            
        case .failure(let err):
            return .failure(err)
        }
    }
    
    func getSignedTransaction(
        inputData: Data,
        signatures: [String: TssKeysignResponse]) -> Result<String, Error>
    {
        let bitcoinPubKey = getDerivedPubKey()
        guard let pubkeyData = Data(hexString: bitcoinPubKey),
              let publicKey = PublicKey(data: pubkeyData, type: .secp256k1)
        else {
            return .failure(HelperError.runtimeError("public key \(bitcoinPubKey) is invalid"))
        }
        
        do {
            let preHashes = TransactionCompiler.preImageHashes(coinType: coin, txInputData: inputData)
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
            let compileWithSignatures = TransactionCompiler.compileWithSignatures(coinType: coin, txInputData: inputData, signatures: allSignatures, publicKeys: publicKeys)
            let output = try BitcoinSigningOutput(serializedData: compileWithSignatures)
            return .success(output.encoded.hexString)
        } catch {
            return .failure(HelperError.runtimeError("fail to construct raw transaction,error: \(error.localizedDescription)"))
        }
    }
}
