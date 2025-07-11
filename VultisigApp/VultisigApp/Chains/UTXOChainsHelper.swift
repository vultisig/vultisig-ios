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
    
    func getSwapPreSignedInputData(keysignPayload: KeysignPayload) throws -> BitcoinSigningInput {
        guard let swapPayload = keysignPayload.swapPayload else {
            throw HelperError.runtimeError("swap payload is nil")
        }
        guard case .thorchain(let thorChainSwapPayload) = swapPayload else {
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
        }
        
        return input
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
            plan.branchID = Data(hexString: "5510e7c8")! // Correct hex string
        }
        
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

        if coin == .zcash {
            plan.branchID = Data(hexString: "5510e7c8")! // Correct hex string
        }

        input.plan = plan
        return try input.serializedData()
    }

    func getBitcoinTransactionPlan(keysignPayload: KeysignPayload) throws -> BitcoinTransactionPlan {
        let input = try getBitcoinSigningInput(keysignPayload: keysignPayload)
        var plan: BitcoinTransactionPlan = AnySigner.plan(input: input, coin: coin)

        if coin == .zcash {
            plan .branchID = Data(hexString: "5510e7c8")! // Correct hex string
        }
        
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
    
    /// Creates a valid Bitcoin transaction for security scanning purposes
    /// This generates a transaction that can be validated before actual TSS signing
    func getValidatedTransaction(keysignPayload: KeysignPayload) throws -> String {
        print("Creating validated transaction for security scanning...")
        print("Coin type: \(coin)")
        print("UTXOs count: \(keysignPayload.utxos.count)")
        
        // For Blockaid, we need a properly formatted Bitcoin transaction
        // We'll use WalletCore's transaction builder with a dummy key
        
        do {
            // Create a dummy private key
            let dummyPrivateKeyData = Data(hexString: "0000000000000000000000000000000000000000000000000000000000000001")!
            let dummyPrivateKey = PrivateKey(data: dummyPrivateKeyData)!
            
            // Get the public key from the dummy private key
            let dummyPublicKey = dummyPrivateKey.getPublicKeySecp256k1(compressed: true)
            
            // Create signing input
            var input = try getBitcoinSigningInput(keysignPayload: keysignPayload)
            
            // Get the plan
            let plan: BitcoinTransactionPlan = AnySigner.plan(input: input, coin: coin)
            input.plan = plan
            
            print("Transaction plan: fee=\(plan.fee), change=\(plan.change)")
            
            // Create pre-signing output to get the hashes we need to sign
            let inputData = try input.serializedData()
            let preHashes = TransactionCompiler.preImageHashes(coinType: coin, txInputData: inputData)
            let preSignOutputs = try BitcoinPreSigningOutput(serializedBytes: preHashes)
            
            if !preSignOutputs.errorMessage.isEmpty {
                print("Pre-signing error: \(preSignOutputs.errorMessage)")
                throw HelperError.runtimeError(preSignOutputs.errorMessage)
            }
            
            // Create signatures using the dummy private key
            let allSignatures = DataVector()
            let publicKeys = DataVector()
            
            for hashPublicKey in preSignOutputs.hashPublicKeys {
                let preImageHash = hashPublicKey.dataHash
                
                // Sign with dummy private key
                let signature = dummyPrivateKey.sign(digest: preImageHash, curve: .secp256k1)!
                
                // Convert to DER format
                let r = Array(signature.prefix(32))
                let s = Array(signature[32..<64])
                let derSignature = encodeCanonicalDERSignature(r: r, s: s)
                
                allSignatures.add(data: derSignature)
                publicKeys.add(data: dummyPublicKey.data)
            }
            
            // Compile the transaction with signatures
            let compiledOutput = TransactionCompiler.compileWithSignatures(
                coinType: coin,
                txInputData: inputData,
                signatures: allSignatures,
                publicKeys: publicKeys
            )
            
            print("Compiled transaction size: \(compiledOutput.count) bytes")
            
            // Parse the output to check for errors
            let output = try BitcoinSigningOutput(serializedBytes: compiledOutput)
            
            if !output.errorMessage.isEmpty {
                print("Compilation error: \(output.errorMessage)")
                throw HelperError.runtimeError(output.errorMessage)
            }
            
            if output.encoded.isEmpty || output.encoded.count < 10 {
                print("Warning: Compiled output is too small (\(output.encoded.count) bytes)")
                throw HelperError.runtimeError("Invalid transaction output")
            }
            
            print("Successfully created validated Bitcoin transaction")
            print("Transaction ID: \(output.transactionID)")
            print("Transaction hex: \(output.encoded.hexString.prefix(100))...")
            
            return output.encoded.hexString
            
        } catch {
            print("Error creating validated transaction: \(error)")
            throw HelperError.runtimeError("Failed to create validated transaction: \(error.localizedDescription)")
        }
    }
}
