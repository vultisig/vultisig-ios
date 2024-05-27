//
//  maya.swift
//  VultisigApp
//
//  Created by Johnny Luo on 17/4/2024.
//

import Foundation
import Tss
import WalletCore
import CryptoSwift

enum MayaChainHelper {
    static let MayaChainGas: UInt64 = 2000000000
    
    static func getMayaCoin(hexPubKey: String, hexChainCode: String, coinTicker: String) -> Result<Coin, Error> {
        let derivePubKey = PublicKeyHelper.getDerivedPubKey(hexPubKey: hexPubKey,
                                                            hexChainCode: hexChainCode,
                                                            derivePath: CoinType.thorchain.derivationPath())
        if derivePubKey.isEmpty {
            return .failure(HelperError.runtimeError("derived public key is empty"))
        }
        return getAddressFromPublicKey(hexPubKey: hexPubKey, hexChainCode: hexChainCode).flatMap { addr -> Result<Coin, Error> in
            TokensStore.createNewCoinInstance(ticker: coinTicker, address: addr, hexPublicKey: derivePubKey, coinType: .thorchain)
        }
    }
    
    static func getAddressFromPublicKey(hexPubKey: String, hexChainCode: String) -> Result<String, Error> {
        let derivePubKey = PublicKeyHelper.getDerivedPubKey(hexPubKey: hexPubKey,
                                                            hexChainCode: hexChainCode,
                                                            derivePath: CoinType.thorchain.derivationPath())
        if derivePubKey.isEmpty {
            return .failure(HelperError.runtimeError("derived public key is empty"))
        }
        guard let pubKeyData = Data(hexString: derivePubKey), let publicKey = PublicKey(data: pubKeyData, type: .secp256k1) else {
            return .failure(HelperError.runtimeError("public key: \(derivePubKey) is invalid"))
        }
        let mayaAddress = AnyAddress(publicKey: publicKey, coin: .thorchain, hrp: "maya")
        return .success(mayaAddress.description)
    }
    
    static func getSwapPreSignedInputData(keysignPayload: KeysignPayload, signingInput: CosmosSigningInput) -> Result<Data, Error> {
        guard case .MayaChain(let accountNumber, let sequence) = keysignPayload.chainSpecific else {
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
        // THORChain fee is 0.02 RUNE
        input.fee = CosmosFee.with {
            $0.gas = MayaChainGas
            $0.amounts = [CosmosAmount.with {
                $0.denom = "cacao"
                $0.amount = MayaChainGas.description
            }]
        }
        print(input.debugDescription)
        // memo has been set
        // deposit message has been set
        do {
            let inputData = try input.serializedData()
            return .success(inputData)
        } catch {
            return .failure(HelperError.runtimeError("fail to get plan"))
        }
    }
    
    static func getPreSignedInputData(keysignPayload: KeysignPayload) -> Result<Data, Error> {
        
        guard let fromAddr = AnyAddress(string: keysignPayload.coin.address, coin: .thorchain, hrp: "maya") else {
            return .failure(HelperError.runtimeError("\(keysignPayload.coin.address) is invalid"))
        }

        guard case .MayaChain(let accountNumber, let sequence) = keysignPayload.chainSpecific else {
            return .failure(HelperError.runtimeError("fail to get account number and sequence"))
        }
        guard let pubKeyData = Data(hexString: keysignPayload.coin.hexPublicKey) else {
            return .failure(HelperError.runtimeError("invalid hex public key"))
        }
        let coin = CoinType.thorchain

        var mayaChainCoin = TW_Cosmos_Proto_THORChainCoin()
        var message = [CosmosMessage()]

        var isDeposit: Bool = false
        if let memo = keysignPayload.memo, !memo.isEmpty {
            if DepositStore.PREFIXES.contains(where: { memo.hasPrefix($0) }) {
                isDeposit = true
            }
        }

        if isDeposit {
            mayaChainCoin = TW_Cosmos_Proto_THORChainCoin.with {
                $0.asset = TW_Cosmos_Proto_THORChainAsset.with {
                    $0.chain = "MAYA"
                    $0.symbol = "CACAO"
                    $0.ticker = "CACAO"
                    $0.synth = false
                }
                $0.amount = String(keysignPayload.toAmount)
                $0.decimals = 8
            }
            message = [CosmosMessage.with {
                $0.thorchainDepositMessage = CosmosMessage.THORChainDeposit.with {
                    $0.signer = fromAddr.data
                    $0.memo = keysignPayload.memo ?? ""
                    $0.coins = [mayaChainCoin]
                }
            }]
        } else {
            guard let toAddress = AnyAddress(string: keysignPayload.toAddress, coin: .thorchain, hrp: "maya") else {
                return .failure(HelperError.runtimeError("\(keysignPayload.toAddress) is invalid"))
            }

            message = [CosmosMessage.with {
                $0.thorchainSendMessage = CosmosMessage.THORChainSend.with {
                    $0.fromAddress = fromAddr.data
                    $0.amounts = [CosmosAmount.with {
                        $0.denom = keysignPayload.coin.ticker.lowercased()
                        $0.amount = String(keysignPayload.toAmount)
                    }]
                    $0.toAddress = toAddress.data
                }
            }]
        }

        let input = CosmosSigningInput.with {
            $0.publicKey = pubKeyData
            $0.signingMode = .protobuf
            $0.chainID = "mayachain-mainnet-v1"
            $0.accountNumber = accountNumber
            $0.sequence = sequence
            $0.mode = .sync
            if let memo = keysignPayload.memo {
                $0.memo = memo
            }
            $0.messages = message
            // MAYAChain fee is 0.02 CACAO
            $0.fee = CosmosFee.with {
                $0.gas = MayaChainGas
                $0.amounts = [CosmosAmount.with {
                    $0.denom = "cacao"
                    $0.amount = MayaChainGas.description
                }]
            }
        }
        do {
            let inputData = try input.serializedData()
            return .success(inputData)
        } catch {
            return .failure(HelperError.runtimeError("fail to get plan"))
        }
    }
    
    static func getPreSignedImageHash(keysignPayload: KeysignPayload) -> Result<[String], Error> {
        let result = getPreSignedInputData(keysignPayload: keysignPayload)
        switch result {
        case .success(let inputData):
            do {
                let hashes = TransactionCompiler.preImageHashes(coinType: .thorchain, txInputData: inputData)
                let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
                return .success([preSigningOutput.dataHash.hexString])
            } catch {
                return .failure(HelperError.runtimeError("fail to get preSignedImageHash,error:\(error.localizedDescription)"))
            }
        case .failure(let err):
            return .failure(err)
        }
    }
    
    static func getSignedTransaction(vaultHexPubKey: String,
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
    
    static func getSignedTransaction(vaultHexPubKey: String,
                                     vaultHexChainCode: String,
                                     inputData: Data,
                                     signatures: [String: TssKeysignResponse]) -> Result<SignedTransactionResult, Error>
    {
        let thorPublicKey = PublicKeyHelper.getDerivedPubKey(hexPubKey: vaultHexPubKey, hexChainCode: vaultHexChainCode, derivePath: CoinType.thorchain.derivationPath())
        guard let pubkeyData = Data(hexString: thorPublicKey),
              let publicKey = PublicKey(data: pubkeyData, type: .secp256k1)
        else {
            return .failure(HelperError.runtimeError("public key \(thorPublicKey) is invalid"))
        }
        
        do {
            let hashes = TransactionCompiler.preImageHashes(coinType: .thorchain, txInputData: inputData)
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
            let compileWithSignature = TransactionCompiler.compileWithSignatures(coinType: .thorchain,
                                                                                 txInputData: inputData,
                                                                                 signatures: allSignatures,
                                                                                 publicKeys: publicKeys)
            let output = try CosmosSigningOutput(serializedData: compileWithSignature)
            let serializedData = output.serialized
            let sig = try JSONDecoder().decode(CosmosSignature.self, from: serializedData.data(using: .utf8) ?? Data())
            let result = SignedTransactionResult(rawTransaction: serializedData, transactionHash:sig.getTransactionHash())
            return .success(result)
        } catch {
            return .failure(HelperError.runtimeError("fail to get signed ethereum transaction,error:\(error.localizedDescription)"))
        }
    }
}
