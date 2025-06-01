//
//  eth.swift
//  VultisigApp
//

import BigInt
import Foundation
import Tss
import WalletCore
import CryptoSwift

class EVMHelper {
    static let defaultETHTransferGasUnit:Int64 = 23000 // Increased to 23000 to support swaps and transfers with memo
    static let defaultETHSwapGasUnit:Int64 = 600000
    static let defaultERC20TransferGasUnit:Int64 = 120000
    static let weiPerGWei: Int64 = 1_000_000_000
    static let wei: Int64 = 1_000_000_000_000_000_000
    
    static let ethDecimals = 18
    let coinType: CoinType
    
    init(coinType: CoinType) {
        self.coinType = coinType
    }
    
    static func getHelper(coin: Coin) -> EVMHelper {
        return EVMHelper(coinType: coin.coinType)
    }
    
    func getPreSignedInputData(
        signingInput: EthereumSigningInput,
        keysignPayload: KeysignPayload,
        gas: BigUInt? = nil,
        gasPrice: BigUInt? = nil,
        incrementNonce: Bool = false) throws -> Data
    {
        guard let intChainID = Int(getChainId(chain: keysignPayload.coin.chain)) else {
            throw HelperError.runtimeError("fail to get chainID")
        }

        guard case .Ethereum(
            let maxFeePerGasWei,
            let priorityFeeWei,
            let nonce,
            let gasLimit
        ) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get Ethereum chain specific")
        }

        let incrementNonceValue: Int64 = incrementNonce ? 1 : 0

        var input = signingInput
        input.chainID = Data(hexString: Int64(intChainID).hexString())!
        input.nonce = Data(hexString: (nonce + incrementNonceValue).hexString())!

        if let gas, let gasPrice {
            input.gasLimit = gas.serialize()
            input.gasPrice = gasPrice.serialize()
            input.txMode = .legacy
        } else {
            input.gasLimit = gasLimit.magnitude.serialize()
            input.maxFeePerGas = maxFeePerGasWei.magnitude.serialize()
            input.maxInclusionFeePerGas = priorityFeeWei.magnitude.serialize()
            input.txMode = .enveloped
        }

        if let gasLimitInt = Int(input.gasLimit.hexString, radix: 16) {
            print("🔧 TxBuilder: Gas limit: \(gasLimitInt)")
        }
        
        if input.txMode == .legacy {
            if let gasPriceInt = Int(input.gasPrice.hexString, radix: 16) {
                print("🔧 TxBuilder: Gas Price: \(gasPriceInt)")
            }
        } else {
            if let maxFeeInt = Int(input.maxFeePerGas.hexString, radix: 16) {
                print("🔧 TxBuilder: Max fee per gas: \(maxFeeInt)")
            }
        }
        
        return try input.serializedData()
    }
    func getChainId(chain: Chain) -> String {
        if chain == Chain.ethereumSepolia {
            return "11155111"
        }
        return self.coinType.chainId
    }
    func getPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {

        guard let intChainID = Int(getChainId(chain: keysignPayload.coin.chain)) else {
            print("⚙️ EVMHelper: ⚠️ Failed to get chainID")
            throw HelperError.runtimeError("fail to get chainID")
        }
        
        guard case .Ethereum(let maxFeePerGasWei,
                             let priorityFeeWei,
                             let nonce,
                             let gasLimit) = keysignPayload.chainSpecific
        else {
            print("⚙️ EVMHelper: ⚠️ Failed to get Ethereum chain specific")
            throw HelperError.runtimeError("fail to get Ethereum chain specific")
        }

        let input = EthereumSigningInput.with {
            $0.chainID = Data(hexString: Int64(intChainID).hexString())!
            $0.nonce = Data(hexString: nonce.hexString())!
            $0.gasLimit = gasLimit.magnitude.serialize()
            $0.maxFeePerGas = maxFeePerGasWei.magnitude.serialize()
            $0.maxInclusionFeePerGas = priorityFeeWei.magnitude.serialize()
            $0.toAddress = keysignPayload.toAddress
            $0.txMode = .enveloped
            
            $0.transaction = EthereumTransaction.with {
                $0.transfer = EthereumTransaction.Transfer.with {
                    $0.amount = keysignPayload.toAmount.serializeForEvm()
                    if let memo = keysignPayload.memo {
                        if memo.hasPrefix("0x") {
                            $0.data = Data(hex: memo)
                        } else {
                            $0.data = Data(memo.utf8)
                        }
                    }
                }
            }
        }
        
        do {
            let serialized = try input.serializedData()
            return serialized
        } catch {
            print("⚙️ EVMHelper: ⚠️ Failed to serialize input: \(error.localizedDescription)")
            throw error
        }
    }
    
    func getPreSignedImageHash(keysignPayload: KeysignPayload) throws -> [String] {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let hashes = TransactionCompiler.preImageHashes(coinType: coinType, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        if !preSigningOutput.errorMessage.isEmpty {
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }
        return [preSigningOutput.dataHash.hexString]
    }
    
    func getSignedTransaction(vaultHexPubKey: String,
                              vaultHexChainCode: String,
                              keysignPayload: KeysignPayload,
                              signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult
    {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let signedTransaction = try getSignedTransaction(vaultHexPubKey: vaultHexPubKey, vaultHexChainCode: vaultHexChainCode, inputData: inputData, signatures: signatures)
        return signedTransaction
    }
    
    func getSignedTransaction(vaultHexPubKey: String,
                              vaultHexChainCode: String,
                              inputData: Data,
                              signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult
    {
        let ethPublicKey = PublicKeyHelper.getDerivedPubKey(hexPubKey: vaultHexPubKey, hexChainCode: vaultHexChainCode, derivePath: self.coinType.derivationPath())
        guard let pubkeyData = Data(hexString: ethPublicKey),
              let publicKey = PublicKey(data: pubkeyData, type: .secp256k1)
        else {
            throw HelperError.runtimeError("public key \(ethPublicKey) is invalid")
        }

        let hashes = TransactionCompiler.preImageHashes(coinType: self.coinType, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        let allSignatures = DataVector()
        let publicKeys = DataVector()
        let signatureProvider = SignatureProvider(signatures: signatures)
        let signature = signatureProvider.getSignatureWithRecoveryID(preHash: preSigningOutput.dataHash)
        guard publicKey.verify(signature: signature, message: preSigningOutput.dataHash) else {
            throw HelperError.runtimeError("fail to verify signature")
        }

        allSignatures.add(data: signature)

        // it looks like the pubkey compileWithSignature accept is extended public key
        // also , it can be empty as well , since we don't have extended public key , so just leave it empty
        let compileWithSignature = TransactionCompiler.compileWithSignatures(coinType: self.coinType,
                                                                             txInputData: inputData,
                                                                             signatures: allSignatures,
                                                                             publicKeys: publicKeys)
        let output = try EthereumSigningOutput(serializedBytes: compileWithSignature)
        let result = SignedTransactionResult(rawTransaction: output.encoded.hexString,
                                             transactionHash: "0x"+output.encoded.sha3(.keccak256).toHexString())
        
        return result
    }
}
