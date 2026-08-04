//
//  Sui.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 23/04/24.
//

import Foundation
import Tss
import WalletCore
import BigInt

enum SuiHelper {

    static func getPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        guard keysignPayload.coin.chain == .sui else {
            throw HelperError.runtimeError("coin is not SUI")
        }

        // dApp-supplied PTBs (Sui Wallet Standard) arrive already BCS-serialized
        // in `signSui`. WalletCore signs them verbatim via `signDirectMessage`:
        // coins, gas and recipients are baked into the bytes, so we never
        // reconstruct a Pay / PaySui input. WalletCore hashes `unsignedTxMsg`
        // under the transaction intent, exactly like the native path.
        if let signSui = keysignPayload.signSui {
            let input = SuiSigningInput.with {
                $0.signer = keysignPayload.coin.address
                $0.signDirectMessage = SuiSignDirect.with {
                    $0.unsignedTxMsg = signSui.unsignedTxMsg
                }
            }
            return try input.serializedData()
        }

        guard case .Sui(let referenceGasPrice, let coins, let gasBudget) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("getPreSignedInputData fail to get SUI transaction information from RPC")
        }

        guard let amountValue = UInt64(exactly: keysignPayload.toAmount),
              let gasBudgetValue = UInt64(exactly: gasBudget),
              let referenceGasPriceValue = UInt64(exactly: referenceGasPrice) else {
            throw HelperError.runtimeError("SUI transaction amount or gas values are out of range")
        }

        guard let toAddress = AnyAddress(string: keysignPayload.toAddress, coin: .sui) else {
            throw HelperError.runtimeError("fail to get to address")
        }

        guard !coins.isEmpty else {
            throw HelperError.runtimeError("No coins available for transaction")
        }

        if keysignPayload.coin.isNativeToken {

            let nativeCoins = coins.filter { SuiCoinType.isNative($0["coinType"] ?? .empty) }
            guard !nativeCoins.isEmpty else {
                throw HelperError.runtimeError("Native token transaction requires at least one SUI coin")
            }

            // Reference only the largest objects needed to fund amount + gas.
            // PaySui uses its whole input set as the gas payment, which Sui
            // gas-smashes into one coin — so a scattered balance is still merged,
            // but the transaction stays within Sui's 128 KiB size / 256-gas-object
            // limits instead of referencing every object and failing at broadcast.
            let target = keysignPayload.toAmount + gasBudget
            let selectedCoins = SuiCoinType.selectInputCoins(nativeCoins, covering: target)
            guard SuiCoinType.covers(selectedCoins, target: target) else {
                throw HelperError.runtimeError("Insufficient SUI balance in the selected coin objects")
            }
            let suiCoins = try selectedCoins.map(objectRef(from:))

            let input = SuiSigningInput.with {
                $0.paySui = SuiPaySui.with {
                    $0.inputCoins = suiCoins
                    $0.recipients = [toAddress.description]
                    $0.amounts = [amountValue]
                }
                $0.signer = keysignPayload.coin.address
                $0.gasBudget = gasBudgetValue
                $0.referenceGasPrice = referenceGasPriceValue
            }

            return try input.serializedData()

        } else {
            let tokenCoinType = SuiCoinType.expectedType(
                isNativeToken: keysignPayload.coin.isNativeToken,
                contractAddress: keysignPayload.coin.contractAddress
            )
            guard !keysignPayload.coin.contractAddress.isEmpty,
                  !SuiCoinType.isNative(tokenCoinType) else {
                throw HelperError.runtimeError("Non-native SUI token transaction has an invalid coin type")
            }
            let tokenCoins = coins.filter {
                let coinType = $0["coinType"] ?? .empty
                return SuiCoinType.matches(coinType, tokenCoinType) && !SuiCoinType.isNative(coinType)
            }
            guard !tokenCoins.isEmpty else {
                throw HelperError.runtimeError("Non-native token transaction requires the token to be present")
            }

            // Reference only the largest token objects needed to fund the amount.
            // WalletCore's Pay merges the input coins in-PTB before splitting, so a
            // scattered token balance is still spendable while the transaction
            // stays within Sui's size limit instead of referencing every object.
            let selectedCoins = SuiCoinType.selectInputCoins(tokenCoins, covering: keysignPayload.toAmount)
            guard SuiCoinType.covers(selectedCoins, target: keysignPayload.toAmount) else {
                throw HelperError.runtimeError("Insufficient token balance in the selected SUI coin objects")
            }
            let suiCoins = try selectedCoins.map(objectRef(from:))

            // A token send pays gas from a single SUI object (WalletCore's
            // `Sui.Pay` gas field is not gas-smashed like `PaySui`), so select
            // the smallest native SUI object that covers the budget instead of an
            // arbitrary one — otherwise the send fails when the first object is
            // too small even though the wallet holds enough SUI elsewhere.
            guard let gasObjectDict = SuiCoinType.selectGasObject(coins, gasBudget: gasBudget) else {
                throw HelperError.runtimeError("No single SUI coin object can cover the gas fee")
            }
            let gasObject = try objectRef(from: gasObjectDict)

            let input = SuiSigningInput.with {
                $0.pay = SuiPay.with {
                    $0.inputCoins = suiCoins
                    $0.recipients = [toAddress.description]
                    $0.amounts = [amountValue]
                    $0.gas = gasObject
                }
                $0.signer = keysignPayload.coin.address
                $0.gasBudget = gasBudgetValue
                $0.referenceGasPrice = referenceGasPriceValue
            }

            return try input.serializedData()
        }

    }

    /// Builds a WalletCore `SuiObjectRef` from a validated coin-object dictionary.
    private static func objectRef(from coin: [String: String]) throws -> SuiObjectRef {
        guard let objectID = coin["objectID"], !objectID.isEmpty,
              let versionString = coin["version"], let version = UInt64(versionString),
              let objectDigest = coin["objectDigest"], !objectDigest.isEmpty else {
            throw HelperError.runtimeError(
                "Malformed SUI coin object: objectID, version, and objectDigest are required"
            )
        }
        var obj = SuiObjectRef()
        obj.objectID = objectID
        obj.version = version
        obj.objectDigest = objectDigest
        return obj
    }

    static func getPreSignedImageHash(keysignPayload: KeysignPayload) throws -> [String] {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let hashes = TransactionCompiler.preImageHashes(coinType: .sui, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        if !preSigningOutput.errorMessage.isEmpty {
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }
        return [Hash.blake2b(data: preSigningOutput.data, size: 32).hexString]
    }

    static func getSignedTransaction(keysignPayload: KeysignPayload,
                                     signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult {
        let coinHexPublicKey = keysignPayload.coin.hexPublicKey
        guard let pubkeyData = Data(hexString: coinHexPublicKey) else {
            throw HelperError.runtimeError("public key \(coinHexPublicKey) is invalid")
        }
        guard let publicKey = PublicKey(data: pubkeyData, type: .ed25519) else {
            throw HelperError.runtimeError("public key \(coinHexPublicKey) is invalid")
        }

        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let hashes = TransactionCompiler.preImageHashes(coinType: .sui, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        let preSigningOutputDataBlake2b = Hash.blake2b(data: preSigningOutput.data, size: 32)
        let allSignatures = DataVector()
        let publicKeys = DataVector()
        let signatureProvider = SignatureProvider(signatures: signatures)
        let signature = signatureProvider.getSignature(preHash: preSigningOutputDataBlake2b)

        guard publicKey.verify(signature: signature, message: preSigningOutputDataBlake2b) else {
            throw HelperError.runtimeError("SUI signature verification failed")
        }

        allSignatures.add(data: signature)
        publicKeys.add(data: pubkeyData)
        let compileWithSignature = TransactionCompiler.compileWithSignatures(coinType: .sui,
                                                                             txInputData: inputData,
                                                                             signatures: allSignatures,
                                                                             publicKeys: publicKeys)
        let output = try SuiSigningOutput(serializedBytes: compileWithSignature)
        let result = SignedTransactionResult(rawTransaction: output.unsignedTx, transactionHash: .empty, signature: output.signature)
        return result
    }

    static func getZeroSignedTransaction(keysignPayload: KeysignPayload) throws -> String {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let hashes = TransactionCompiler.preImageHashes(coinType: .sui, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)

        // Drop 3 first bytes which represents signature, they're added by WalletCore
        // but for simulations or blockaid is not required
        let tx = Data(preSigningOutput.data.dropFirst(3))

        return Base64.encode(data: tx)
    }
}
