//
//  CosmosHelperStruct.swift
//  VultisigApp
//
//  Refactored to use struct (value type) instead of classes
//

import Foundation
import WalletCore
import Tss
import CryptoSwift
import VultisigCommonData

struct CosmosHelperStruct {
    let config: CosmosHelperConfig

    func getSwapPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        guard let swapPayload = keysignPayload.swapPayload else {
            throw HelperError.runtimeError("swap payload is nil")
        }
        let thorChainSwapPayload: THORChainSwapPayload
        switch swapPayload {
        case .thorchain(let payload), .thorchainChainnet(let payload), .thorchainStagenet(let payload):
            thorChainSwapPayload = payload
        default:
            throw HelperError.runtimeError("fail to get swap payload")
        }
        guard let memo = keysignPayload.memo else {
            throw HelperError.runtimeError("swap payload memo is nil")
        }

        guard case .Cosmos(let accountNumber, let sequence, let gas, _, _) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get account number and sequence")
        }
        guard let pubKeyData = Data(hexString: keysignPayload.coin.hexPublicKey) else {
            throw HelperError.runtimeError("invalid hex public key")
        }
        let input = try CosmosSigningInput.with {
            $0.publicKey = pubKeyData
            $0.accountNumber = accountNumber
            $0.sequence = sequence
            $0.mode = .sync
            $0.fee = try buildCosmosFee(gas: gas, keysignPayload: keysignPayload)
            $0.signingMode = getSigningMode(keysignPayload: keysignPayload)
            $0.chainID = config.coinType.chainId
            $0.memo = memo
            $0.messages = [WalletCore.CosmosMessage.with {
                $0.sendCoinsMessage = WalletCore.CosmosMessage.Send.with {
                    $0.fromAddress = thorChainSwapPayload.fromAddress
                    $0.toAddress = thorChainSwapPayload.vaultAddress
                    $0.amounts = [CosmosAmount.with {
                        $0.denom = "uatom"
                        $0.amount = String(swapPayload.fromAmount)
                    }]
                }
            }]
        }

        return try input.serializedData()
    }

    func getPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        guard case .Cosmos(let accountNumber, let sequence, let gas, let transactionTypeRawValue, let ibcDenomTrace) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("getPreSignedInputData: fail to get account number and sequence")
        }
        guard let pubKeyData = Data(hexString: keysignPayload.coin.hexPublicKey) else {
            throw HelperError.runtimeError("getPreSignedInputData: invalid hex public key")
        }
        let coin = config.coinType

        var transactionType: VSTransactionType = .unspecified
        if let vsTransactionType = VSTransactionType(rawValue: transactionTypeRawValue) {
            transactionType = vsTransactionType
        }

        switch transactionType {
        case .ibcTransfer:
            var memo = ""
            let splitedMemo = keysignPayload.memo?.split(separator: ":")
            if splitedMemo?.isEmpty ?? true {
                throw HelperError.runtimeError("To send IBC transaction, memo should be specified")
            }

            let sourceChannel = splitedMemo?[1] ?? ""
            if splitedMemo?.count == 4 {
                memo = String(splitedMemo?[3] ?? "")
            }

            let timeouts = ibcDenomTrace?.height?.split(separator: "_") ?? []
            let timeout = UInt64(timeouts.last ?? "0") ?? 0
            let transferMessage = WalletCore.CosmosMessage.Transfer.with {
                $0.sourcePort = "transfer"
                $0.sourceChannel = String(sourceChannel)
                $0.sender = keysignPayload.coin.address
                $0.receiver = String(keysignPayload.toAddress)
                $0.token = CosmosAmount.with {
                    $0.denom = keysignPayload.coin.isNativeToken ? config.denom : keysignPayload.coin.contractAddress
                    $0.amount = String(keysignPayload.toAmount)
                }
                $0.timeoutHeight = CosmosHeight.with {
                    $0.revisionNumber = 0
                    $0.revisionHeight = 0
                }
                $0.timeoutTimestamp = timeout
            }

            let input = try CosmosSigningInput.with {
                $0.publicKey = pubKeyData
                $0.signingMode = getSigningMode(keysignPayload: keysignPayload)
                $0.chainID = coin.chainId
                $0.accountNumber = accountNumber
                $0.sequence = sequence
                $0.mode = .sync
                if !memo.isEmpty {
                    $0.memo = memo
                }
                $0.messages = [WalletCore.CosmosMessage.with { $0.transferTokensMessage = transferMessage }]
                $0.fee = try buildCosmosFee(gas: gas, keysignPayload: keysignPayload)
            }

            return try input.serializedData()
        case .genericContract:
            let (messages, memo) = try buildCosmosMessage(keysignPayload: keysignPayload)
            return try CosmosSigningInput.with {
                $0.publicKey = pubKeyData
                $0.signingMode = getSigningMode(keysignPayload: keysignPayload)
                $0.chainID = coin.chainId
                $0.accountNumber = accountNumber
                $0.sequence = sequence
                $0.mode = .sync
                if let memo = keysignPayload.memo ?? memo {
                    $0.memo = memo
                }
                $0.messages = messages
                $0.fee = try buildCosmosFee(gas: gas, keysignPayload: keysignPayload)
            }.serializedData()
        case .unspecified:
            if keysignPayload.signData != nil {
                let (messages, memo) = try buildCosmosMessage(keysignPayload: keysignPayload)

                return try CosmosSigningInput.with {
                    $0.publicKey = pubKeyData
                    $0.signingMode = getSigningMode(keysignPayload: keysignPayload)
                    $0.chainID = coin.chainId
                    $0.accountNumber = accountNumber
                    $0.sequence = sequence
                    $0.mode = .sync
                    if let memo = keysignPayload.memo ?? memo {
                        $0.memo = memo
                    }
                    $0.messages = messages
                    $0.fee = try buildCosmosFee(gas: gas, keysignPayload: keysignPayload)
                }.serializedData()
            }
        default:
            break
        }

        if keysignPayload.coin.isNativeToken
            || keysignPayload.coin.contractAddress.lowercased().starts(with: "ibc/")
            || keysignPayload.coin.contractAddress.lowercased().starts(with: "factory/")
            || keysignPayload.coin.contractAddress.lowercased().starts(with: "u")
            || (keysignPayload.memo?.lowercased().starts(with: "switch:") == true) {

            let fee = try buildCosmosFee(gas: gas, keysignPayload: keysignPayload)
            let input = CosmosSigningInput.with {
                $0.publicKey = pubKeyData
                $0.signingMode = getSigningMode(keysignPayload: keysignPayload)
                $0.chainID = coin.chainId
                $0.accountNumber = accountNumber
                $0.sequence = sequence
                $0.mode = .sync
                if let memo = keysignPayload.memo {
                    $0.memo = memo
                }
                $0.messages = [WalletCore.CosmosMessage.with {
                    $0.sendCoinsMessage = WalletCore.CosmosMessage.Send.with {
                        $0.fromAddress = keysignPayload.coin.address
                        $0.amounts = [CosmosAmount.with {
                            $0.denom = keysignPayload.coin.isNativeToken ? config.denom : keysignPayload.coin.contractAddress
                            $0.amount = String(keysignPayload.toAmount)
                        }]
                        $0.toAddress = keysignPayload.toAddress
                    }
                }]

                $0.fee = fee
            }

            return try input.serializedData()

        }

        throw HelperError.runtimeError("It must be a native token or a valid IBC token")
    }

    func getPreSignedImageHash(keysignPayload: KeysignPayload) throws -> [String] {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)

        let hashes = TransactionCompiler.preImageHashes(coinType: config.coinType, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        if !preSigningOutput.errorMessage.isEmpty {
            print("Error getPreSignedImageHash: \(preSigningOutput.errorMessage)")
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }

        return [preSigningOutput.dataHash.hexString]
    }

    func getSignedTransaction(keysignPayload: KeysignPayload,
                              signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let signedTransaction = try getSignedTransaction(coinHexPublicKey: keysignPayload.coin.hexPublicKey, inputData: inputData, signatures: signatures)
        return signedTransaction
    }

    func getSignedTransaction(coinHexPublicKey: String,
                              inputData: Data,
                              signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult {
        guard let pubkeyData = Data(hexString: coinHexPublicKey),
              let publicKey = PublicKey(data: pubkeyData, type: .secp256k1)
        else {
            throw HelperError.runtimeError("public key \(coinHexPublicKey) is invalid")
        }

        do {
            let hashes = TransactionCompiler.preImageHashes(coinType: config.coinType, txInputData: inputData)
            let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
            let allSignatures = DataVector()
            let publicKeys = DataVector()
            let signatureProvider = SignatureProvider(signatures: signatures)
            let signature = signatureProvider.getSignatureWithRecoveryID(preHash: preSigningOutput.dataHash)
            guard publicKey.verify(signature: signature, message: preSigningOutput.dataHash) else {
                print("getSignedTransaction signature is invalid")
                throw HelperError.runtimeError("fail to verify signature")
            }

            allSignatures.add(data: signature)
            publicKeys.add(data: pubkeyData)
            let compileWithSignature = TransactionCompiler.compileWithSignatures(coinType: config.coinType,
                                                                                 txInputData: inputData,
                                                                                 signatures: allSignatures,
                                                                                 publicKeys: publicKeys)
            let output = try CosmosSigningOutput(serializedBytes: compileWithSignature)

            if output.errorMessage.isNotEmpty {
                print("getSignedTransaction Error message: \(output.errorMessage)")
            }

            let serializedData = output.serialized
            let transactionHash = CosmosSerializedParser.getTransactionHash(from: serializedData)
            let result = SignedTransactionResult(rawTransaction: serializedData, transactionHash: transactionHash)
            return result
        } catch {
            throw HelperError.runtimeError("fail to get signed transaction,error:\(error.localizedDescription)")
        }
    }

    private func buildCosmosFee(gas: UInt64, keysignPayload: KeysignPayload) throws -> WalletCore.CosmosFee {
        if let signDataFee = try CosmosSignDataBuilder.getFee(keysignPayload: keysignPayload) {
            return signDataFee
        }

        return defaultFee(gas: gas)
    }

    private func defaultFee(gas: UInt64) -> WalletCore.CosmosFee {
        WalletCore.CosmosFee.with {
            $0.gas = config.gasLimit
            $0.amounts = [CosmosAmount.with {
                $0.denom = config.denom
                $0.amount = String(gas)
            }]
        }
    }

    private func buildCosmosWasmGenericMsg(keysignPayload: KeysignPayload) throws -> WalletCore.CosmosMessage {
        let coinType = keysignPayload.coin.chain.coinType

        guard coinType.validate(address: keysignPayload.coin.address) else {
            throw HelperError.runtimeError("Invalid Address type: \(keysignPayload.coin.address)")
        }

        guard let contractPayload = keysignPayload.wasmExecuteContractPayload else {
            throw HelperError.runtimeError("Invalid empty WasmExecuteContractPayload")
        }

        let coins = contractPayload.coins.map { coin in
            CosmosAmount.with {
                $0.denom = coin.denom
                $0.amount = coin.amount
            }
        }

        return WalletCore.CosmosMessage.with {
            $0.wasmExecuteContractGeneric = WalletCore.CosmosMessage.WasmExecuteContractGeneric.with {
                $0.senderAddress = contractPayload.senderAddress
                $0.contractAddress = contractPayload.contractAddress
                $0.executeMsg = contractPayload.executeMsg
                $0.coins = coins
            }
        }
    }

    func buildCosmosMessage(keysignPayload: KeysignPayload) throws -> (messages: [WalletCore.CosmosMessage], memo: String?) {
        if let messagesResult = try CosmosSignDataBuilder.getMessages(keysignPayload: keysignPayload) {
            return messagesResult
        }

        return (messages: [try buildCosmosWasmGenericMsg(keysignPayload: keysignPayload)], memo: nil)
    }

    func getSigningMode(keysignPayload: KeysignPayload) -> WalletCore.CosmosSigningMode {
        CosmosSignDataBuilder.getSigningMode(keysignPayload: keysignPayload)
    }
}
