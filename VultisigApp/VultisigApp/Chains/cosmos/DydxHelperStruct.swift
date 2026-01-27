//
//  DydxHelperStruct.swift
//  VultisigApp
//
//  Refactored to use struct (value type) instead of classes
//

import Foundation
import WalletCore
import Tss
import VultisigCommonData

struct DydxHelperStruct {
    static let DydxGasLimit: UInt64 = 2500000000000000

    static func getPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        guard case .Cosmos(let accountNumber, let sequence, let gas, let transactionTypeRawValue, _) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get account number and sequence")
        }
        guard let pubKeyData = Data(hexString: keysignPayload.coin.hexPublicKey) else {
            throw HelperError.runtimeError("invalid hex public key")
        }
        let coin = CoinType.dydx

        var messages = [WalletCore.CosmosMessage()]
        var memo: String? = keysignPayload.memo

        var transactionType: VSTransactionType = .unspecified
        if let vsTransactionType = VSTransactionType(rawValue: transactionTypeRawValue) {
            transactionType = vsTransactionType
        }

        if transactionType == .vote {
            let selectedOption = keysignPayload.memo?.replacingOccurrences(of: "DYDX_VOTE:", with: "") ?? ""
            let components = selectedOption.split(separator: ":")

            guard components.count == 2,
                  let proposalID = Int(components[1]),
                  let voteOption = TW_Cosmos_Proto_Message.VoteOption.allCases.first(where: { $0.description == String(components[0]) }) else {
                throw HelperError.runtimeError("The vote option is invalid")
            }

            messages = [WalletCore.CosmosMessage.with {
                $0.msgVote = WalletCore.CosmosMessage.MsgVote.with {
                    $0.proposalID = UInt64(proposalID)
                    $0.voter = keysignPayload.coin.address
                    $0.option = voteOption
                }
            }]
        } else {
            guard AnyAddress(string: keysignPayload.toAddress, coin: coin) != nil else {
                throw HelperError.runtimeError("\(keysignPayload.toAddress) is invalid")
            }

            if let signDataMessagesResult = try CosmosSignDataBuilder.getMessages(keysignPayload: keysignPayload) {
                messages = signDataMessagesResult.messages
                if let signDataMemo = signDataMessagesResult.memo {
                    memo = signDataMemo
                }
            } else {
                messages = [WalletCore.CosmosMessage.with {
                    $0.sendCoinsMessage = WalletCore.CosmosMessage.Send.with {
                        $0.fromAddress = keysignPayload.coin.address
                        $0.amounts = [CosmosAmount.with {
                            $0.denom = "adydx"
                            $0.amount = String(keysignPayload.toAmount)
                        }]
                        $0.toAddress = keysignPayload.toAddress
                    }
                }]
            }
        }

        let fee: WalletCore.CosmosFee

        if let signDataFee = try CosmosSignDataBuilder.getFee(keysignPayload: keysignPayload) {
            fee = signDataFee
        } else {
            fee = WalletCore.CosmosFee.with {
                $0.gas = 200000 // gas limit
                $0.amounts = [CosmosAmount.with {
                    $0.denom = "adydx"
                    $0.amount = String(gas)
                }]
            }
        }

        let input = CosmosSigningInput.with {
            $0.publicKey = pubKeyData
            $0.signingMode = CosmosSignDataBuilder.getSigningMode(keysignPayload: keysignPayload)
            $0.chainID = coin.chainId
            $0.accountNumber = accountNumber
            $0.sequence = sequence
            $0.mode = .sync
            if let memo, transactionType != .vote {
                $0.memo = memo
            }
            $0.messages = messages
            $0.fee = fee
        }

        return try input.serializedData()
    }

    static func getPreSignedImageHash(keysignPayload: KeysignPayload) throws -> [String] {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let hashes = TransactionCompiler.preImageHashes(coinType: .dydx, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        if !preSigningOutput.errorMessage.isEmpty {
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }
        return [preSigningOutput.dataHash.hexString]
    }

    static func getSignedTransaction(keysignPayload: KeysignPayload,
                                     signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let signedTransaction = try getSignedTransaction(coinHexPublicKey: keysignPayload.coin.hexPublicKey, inputData: inputData, signatures: signatures)
        return signedTransaction
    }

    static func getSignedTransaction(coinHexPublicKey: String,
                                     inputData: Data,
                                     signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult {
        guard let pubkeyData = Data(hexString: coinHexPublicKey),
              let publicKey = PublicKey(data: pubkeyData, type: .secp256k1)
        else {
            throw HelperError.runtimeError("public key \(coinHexPublicKey) is invalid")
        }

        do {
            let hashes = TransactionCompiler.preImageHashes(coinType: .dydx, txInputData: inputData)
            let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
            let allSignatures = DataVector()
            let publicKeys = DataVector()
            let signatureProvider = SignatureProvider(signatures: signatures)
            let signature = signatureProvider.getSignatureWithRecoveryID(preHash: preSigningOutput.dataHash)
            guard publicKey.verify(signature: signature, message: preSigningOutput.dataHash) else {
                throw HelperError.runtimeError("fail to verify signature")
            }

            allSignatures.add(data: signature)
            publicKeys.add(data: pubkeyData)
            let compileWithSignature = TransactionCompiler.compileWithSignatures(coinType: .dydx,
                                                                                 txInputData: inputData,
                                                                                 signatures: allSignatures,
                                                                                 publicKeys: publicKeys)
            let output = try CosmosSigningOutput(serializedBytes: compileWithSignature)
            let serializedData = output.serialized
            let transactionHash = CosmosSerializedParser.getTransactionHash(from: serializedData)
            let result = SignedTransactionResult(rawTransaction: serializedData, transactionHash: transactionHash)
            return result
        } catch {
            throw HelperError.runtimeError("fail to get signed dydx transaction,error:\(error.localizedDescription)")
        }
    }
}
