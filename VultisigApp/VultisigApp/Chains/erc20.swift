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
    
    func getPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        print("💰 ERC20: Building transaction for \(keysignPayload.coin.ticker) on \(keysignPayload.coin.chain.rawValue)")
        print("💰 ERC20: Contract address: \(keysignPayload.coin.contractAddress)")
        print("💰 ERC20: To address: \(keysignPayload.toAddress)")
        print("💰 ERC20: Amount: \(keysignPayload.toAmount)")
        
        guard let intChainID = Int64(getChainId(chain: keysignPayload.coin.chain)) else {
            throw HelperError.runtimeError("fail to get chainID")
        }
        print("💰 ERC20: Chain ID: \(intChainID)")
        
        guard case .Ethereum(let maxFeePerGasWei,
                          let priorityFeeWei,
                          let nonce,
                          let gasLimit) = keysignPayload.chainSpecific
        else {
            throw HelperError.runtimeError("fail to get Ethereum chain specific")
        }
        
        print("💰 ERC20: Fee parameters from chain specific:")
        print("💰 ERC20: Max fee per gas: \(maxFeePerGasWei)")
        print("💰 ERC20: Priority fee: \(priorityFeeWei)")
        print("💰 ERC20: Nonce: \(nonce)")
        print("💰 ERC20: Gas limit: \(gasLimit)")
        
        let input = EthereumSigningInput.with {
            $0.chainID = Data(hexString: intChainID.hexString())!
            $0.nonce = Data(hexString: nonce.hexString())!
            $0.gasLimit = gasLimit.magnitude.serialize()
            $0.maxFeePerGas = maxFeePerGasWei.magnitude.serialize()
            $0.maxInclusionFeePerGas = priorityFeeWei.magnitude.serialize()
            $0.toAddress = keysignPayload.coin.contractAddress
            $0.txMode = .enveloped
            
            print("💰 ERC20: Serialized gas parameters:")
            print("💰 ERC20: Gas limit: \($0.gasLimit.hexString)")
            print("💰 ERC20: Max fee per gas: \($0.maxFeePerGas.hexString)")
            print("💰 ERC20: Priority fee: \($0.maxInclusionFeePerGas.hexString)")
            
            $0.transaction = EthereumTransaction.with {
                $0.erc20Transfer = EthereumTransaction.ERC20Transfer.with {
                    $0.to = keysignPayload.toAddress
                    $0.amount = keysignPayload.toAmount.serializeForEvm()
                }
            }
        }

        return try input.serializedData()
    }
    
    func getPreSignedImageHash(keysignPayload: KeysignPayload) throws -> [String] {
        print("💰 ERC20: Getting pre-signed image hash")
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        print("💰 ERC20: Input data size: \(inputData.count) bytes")
        
        let hashes = TransactionCompiler.preImageHashes(coinType: coinType, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        if !preSigningOutput.errorMessage.isEmpty {
            print("💰 ERC20: ⚠️ Error in pre-signing: \(preSigningOutput.errorMessage)")
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }
        print("💰 ERC20: Generated hash: \(preSigningOutput.dataHash.hexString)")
        return [preSigningOutput.dataHash.hexString]
    }
    
    func getSignedTransaction(vaultHexPubKey: String,
                                     vaultHexChainCode: String,
                                     keysignPayload: KeysignPayload,
                                     signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult
    {
        print("💰 ERC20: Creating signed transaction for \(keysignPayload.coin.ticker)")
        let ethPublicKey = PublicKeyHelper.getDerivedPubKey(hexPubKey: vaultHexPubKey, hexChainCode: vaultHexChainCode, derivePath: self.coinType.derivationPath())
        guard let pubkeyData = Data(hexString: ethPublicKey),
              let publicKey = PublicKey(data: pubkeyData, type: .secp256k1)
        else {
            throw HelperError.runtimeError("public key \(ethPublicKey) is invalid")
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
        
        print("💰 ERC20: Signed transaction created successfully")
        print("💰 ERC20: Transaction hash: \(result.transactionHash)")
        print("💰 ERC20: Raw transaction first 100 chars: \(result.rawTransaction.prefix(100))...")
        print("💰 ERC20: Transaction size: \(result.rawTransaction.count) chars")
        
        return result
        } catch {
            throw HelperError.runtimeError("fail to get signed ethereum transaction,error:\(error.localizedDescription)")
        }
    }
}
