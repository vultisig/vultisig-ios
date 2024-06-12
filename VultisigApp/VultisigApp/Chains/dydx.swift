//
//  dydx.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 12/06/24.
//

import Foundation
import WalletCore
import Tss
import CryptoSwift

class DydxHelper {
    let coinType: CoinType
    
    init(){
        self.coinType = CoinType.dydx
    }
    
    static let DydxGasLimit:UInt64 = 200000
    
    func getDydxCoin(hexPubKey: String,hexChainCode: String) -> Result<Coin,Error> {
        let derivePubKey = PublicKeyHelper.getDerivedPubKey(hexPubKey: hexPubKey,
                                                            hexChainCode: hexChainCode,
                                                            derivePath: self.coinType.derivationPath())
        if derivePubKey.isEmpty {
            return .failure(HelperError.runtimeError("derived public key is empty"))
        }
        return getAddressFromPublicKey(hexPubKey: hexPubKey, hexChainCode: hexChainCode).flatMap { addr -> Result<Coin, Error> in
            TokensStore.createNewCoinInstance(ticker: "DYDX", address: addr, hexPublicKey: derivePubKey, coinType: self.coinType)
        }
    }
    
    func getAddressFromPublicKey(hexPubKey: String, hexChainCode: String) -> Result<String, Error> {
        let derivePubKey = PublicKeyHelper.getDerivedPubKey(hexPubKey: hexPubKey,
                                                            hexChainCode: hexChainCode,
                                                            derivePath: self.coinType.derivationPath())
        if derivePubKey.isEmpty {
            return .failure(HelperError.runtimeError("derived public key is empty"))
        }
        guard let pubKeyData = Data(hexString: derivePubKey), let publicKey = PublicKey(data: pubKeyData, type: .secp256k1) else {
            return .failure(HelperError.runtimeError("public key: \(derivePubKey) is invalid"))
        }
        return .success(self.coinType.deriveAddressFromPublicKey(publicKey: publicKey))
    }
    
    func getSwapPreSignedInputData(keysignPayload: KeysignPayload,signingInput: CosmosSigningInput) -> Result<Data,Error> {
        guard case .Cosmos(let accountNumber, let sequence,let gas) = keysignPayload.chainSpecific else {
            return .failure(HelperError.runtimeError("fail to get account number and sequence"))
        }
        guard let pubKeyData = Data(hexString: keysignPayload.coin.hexPublicKey) else {
            return .failure(HelperError.runtimeError("invalid hex public key"))
        }
        var input = signingInput
        input.publicKey = pubKeyData
        input.accountNumber = accountNumber
        input.sequence = sequence
        input.mode = .sync
        
        input.fee = CosmosFee.with {
            $0.gas = DydxHelper.DydxGasLimit
        }
        // memo has been set
        // deposit message has been set
        do {
            let inputData = try input.serializedData()
            return .success(inputData)
        } catch {
            return .failure(HelperError.runtimeError("fail to get plan"))
        }
    }
    
    func getPreSignedInputData(keysignPayload: KeysignPayload) -> Result<Data, Error> {
        guard case .Cosmos(let accountNumber, let sequence , let gas) = keysignPayload.chainSpecific else {
            return .failure(HelperError.runtimeError("fail to get account number and sequence"))
        }
        guard let pubKeyData = Data(hexString: keysignPayload.coin.hexPublicKey) else {
            return .failure(HelperError.runtimeError("invalid hex public key"))
        }
        let coin = self.coinType
        
        let input = CosmosSigningInput.with {
            $0.publicKey = pubKeyData
            $0.signingMode = .protobuf
            $0.chainID = coin.chainId
            $0.accountNumber = accountNumber
            $0.sequence = sequence
            $0.mode = .sync
            if let memo = keysignPayload.memo {
                $0.memo = memo
            }
            $0.messages = [CosmosMessage.with {
                $0.sendCoinsMessage = CosmosMessage.Send.with{
                    $0.fromAddress = keysignPayload.coin.address
                    $0.amounts = [CosmosAmount.with {
                        $0.denom = "adydx"
                        $0.amount = String(keysignPayload.toAmount)
                    }]
                    $0.toAddress = keysignPayload.toAddress
                }
            }]
            
            $0.fee = CosmosFee.with {
                $0.gas = DydxHelper.DydxGasLimit
            }
        }
        
        do {
            let inputData = try input.serializedData()
            return .success(inputData)
        } catch {
            return .failure(HelperError.runtimeError("fail to get plan"))
        }
    }
    func getPreSignedImageHash(keysignPayload: KeysignPayload) -> Result<[String], Error> {
        let result = getPreSignedInputData(keysignPayload: keysignPayload)
        switch result {
        case .success(let inputData):
            do {
                let hashes = TransactionCompiler.preImageHashes(coinType: self.coinType, txInputData: inputData)
                let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
                return .success([preSigningOutput.dataHash.hexString])
            } catch {
                return .failure(HelperError.runtimeError("fail to get preSignedImageHash,error:\(error.localizedDescription)"))
            }
        case .failure(let err):
            return .failure(err)
        }
    }
    
    func getSignedTransaction(vaultHexPubKey: String,
                              vaultHexChainCode: String,
                              keysignPayload: KeysignPayload,
                              signatures: [String: TssKeysignResponse]) -> Result<SignedTransactionResult, Error>
    {
        let result = getPreSignedInputData(keysignPayload: keysignPayload)
        switch result {
        case .success(let inputData):
            return getSignedTransaction(vaultHexPubKey: vaultHexPubKey, vaultHexChainCode: vaultHexChainCode, inputData: inputData, signatures: signatures)
            
        case .failure(let err):
            return .failure(err)
        }
    }
    
    func getSignedTransaction(vaultHexPubKey: String,
                              vaultHexChainCode: String,
                              inputData: Data,
                              signatures: [String: TssKeysignResponse]) -> Result<SignedTransactionResult, Error>
    {
        let cosmosPublicKey = PublicKeyHelper.getDerivedPubKey(hexPubKey: vaultHexPubKey, hexChainCode: vaultHexChainCode, derivePath: self.coinType.derivationPath())
        guard let pubkeyData = Data(hexString: cosmosPublicKey),
              let publicKey = PublicKey(data: pubkeyData, type: .secp256k1)
        else {
            return .failure(HelperError.runtimeError("public key \(cosmosPublicKey) is invalid"))
        }
        
        do {
            let hashes = TransactionCompiler.preImageHashes(coinType: self.coinType, txInputData: inputData)
            let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
            let allSignatures = DataVector()
            let publicKeys = DataVector()
            let signatureProvider = SignatureProvider(signatures: signatures)
            let signature = signatureProvider.getSignatureWithRecoveryID(preHash: preSigningOutput.dataHash)
            guard publicKey.verify(signature: signature, message: preSigningOutput.dataHash) else {
                return .failure(HelperError.runtimeError("fail to verify signature"))
            }
            
            allSignatures.add(data: signature)
            publicKeys.add(data: pubkeyData)
            let compileWithSignature = TransactionCompiler.compileWithSignatures(coinType: self.coinType,
                                                                                 txInputData: inputData,
                                                                                 signatures: allSignatures,
                                                                                 publicKeys: publicKeys)
            let output = try CosmosSigningOutput(serializedData: compileWithSignature)
            let serializedData = output.serialized
            let sig = try JSONDecoder().decode(CosmosSignature.self, from: serializedData.data(using: .utf8) ?? Data())
            let result = SignedTransactionResult(rawTransaction: serializedData, transactionHash:sig.getTransactionHash())
            return .success(result)
        } catch {
            return .failure(HelperError.runtimeError("fail to get signed transaction,error:\(error.localizedDescription)"))
        }
    }
}

