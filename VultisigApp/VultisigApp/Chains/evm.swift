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
    
    static func convertEthereumNumber(input: BigInt) -> Data {
        return input.magnitude.serialize()
    }
    
    func getPreSignedInputData(
        signingInput: EthereumSigningInput,
        keysignPayload: KeysignPayload,
        gas: BigUInt? = nil,
        gasPrice: BigUInt? = nil,
        incrementNonce: Bool = false) throws -> Data
    {

        guard let intChainID = Int(coinType.chainId) else {
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

        return try input.serializedData()
    }
    
    func getPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        let coin = self.coinType
        guard let intChainID = Int(coin.chainId) else {
            throw HelperError.runtimeError("fail to get chainID")
        }
        guard case .Ethereum(let maxFeePerGasWei,
                             let priorityFeeWei,
                             let nonce,
                             let gasLimit) = keysignPayload.chainSpecific
        else {
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
                    print("EVM transfer AMOUNT: \(keysignPayload.toAmount.description)")
                    $0.amount = keysignPayload.toAmount.serializeForEvm()
                    if let memo = keysignPayload.memo {
                        if memo.hasPrefix("0x") {
                            // if memo start with 0x , meaning it is hex encoded string , then let's hex decode it first
                            $0.data = Data(hex: memo)
                        } else {
                            $0.data = Data(memo.utf8)
                        }
                    }
                }
            }
        }
        return try input.serializedData()
    }
    
    func getPreSignedImageHash(keysignPayload: KeysignPayload) throws -> [String] {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let hashes = TransactionCompiler.preImageHashes(coinType: coinType, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
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
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
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
        let output = try EthereumSigningOutput(serializedData: compileWithSignature)
        let result = SignedTransactionResult(rawTransaction: output.encoded.hexString,
                                             transactionHash: "0x"+output.encoded.sha3(.keccak256).toHexString())
        return result
    }
}
