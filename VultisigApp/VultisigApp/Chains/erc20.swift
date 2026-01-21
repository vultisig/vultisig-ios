//
//  erc20.swift
//  VultisigApp
//

import Foundation
import Tss
import WalletCore
import BigInt
import CryptoSwift

class ERC20Helper {
    let coinType: CoinType
    
    init(coinType: CoinType) {
        self.coinType = coinType
    }
    
    static func getHelper(coin: Coin) -> ERC20Helper {
        return ERC20Helper(coinType: coin.coinType)
    }
    
    func getChainId(chain: Chain) -> String {
        if chain == Chain.ethereumSepolia {
            return "11155111"
        }
        return self.coinType.chainId
    }
    
    private func configureGasForChain(
        _ input: inout EthereumSigningInput,
        chain: Chain,
        gasLimit: BigInt,
        maxFeePerGasWei: BigInt,
        priorityFeeWei: BigInt
    ) {
        input.gasLimit = gasLimit.magnitude.serialize()
        // BSC doesn't support EIP-1559, use legacy transaction
        if chain == .bscChain {
            input.txMode = .legacy
            input.gasPrice = maxFeePerGasWei.magnitude.serialize()
        } else {
            input.txMode = .enveloped
            input.maxFeePerGas = maxFeePerGasWei.magnitude.serialize()
            input.maxInclusionFeePerGas = priorityFeeWei.magnitude.serialize()
        }
    }
    
    func getPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {

        guard let intChainID = Int64(getChainId(chain: keysignPayload.coin.chain)) else {
            throw HelperError.runtimeError("fail to get chainID")
        }
        guard case .Ethereum(let maxFeePerGasWei,
                          let priorityFeeWei,
                          let nonce,
                          let gasLimit) = keysignPayload.chainSpecific
        else {
            throw HelperError.runtimeError("fail to get Ethereum chain specific")
        }
        
        var input = EthereumSigningInput.with {
            $0.chainID = Data(hexString: intChainID.hexString())!
            $0.nonce = Data(hexString: nonce.hexString())!
            $0.toAddress = keysignPayload.coin.contractAddress
            $0.transaction = EthereumTransaction.with {
                $0.erc20Transfer = EthereumTransaction.ERC20Transfer.with {
                    $0.to = keysignPayload.toAddress
                    $0.amount = keysignPayload.toAmount.serializeForEvm()
                }
            }
        }
        
        configureGasForChain(
            &input,
            chain: keysignPayload.coin.chain,
            gasLimit: gasLimit,
            maxFeePerGasWei: maxFeePerGasWei,
            priorityFeeWei: priorityFeeWei
        )

        return try input.serializedData()
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
    
    func getSignedTransaction(keysignPayload: KeysignPayload,
                                     signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult {
        let coinHexPublicKey = keysignPayload.coin.hexPublicKey
        guard let pubkeyData = Data(hexString: coinHexPublicKey),
              let publicKey = PublicKey(data: pubkeyData, type: .secp256k1)
        else {
            throw HelperError.runtimeError("public key \(coinHexPublicKey) is invalid")
        }
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        do {
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
        } catch {
            throw HelperError.runtimeError("fail to get signed ethereum transaction,error:\(error.localizedDescription)")
        }
    }
}
