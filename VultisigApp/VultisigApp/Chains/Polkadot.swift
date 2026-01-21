//
//  Polkadot.swift
//  VultisigApp
//

import Foundation
import Tss
import WalletCore
import BigInt

enum PolkadotHelper {

    /*
     Polkadot now uses ONLY dynamic fee calculation - no default fees.
     Fees are calculated in real-time using the payment_queryInfo RPC method.
     */

    /*
     https://support.polkadot.network/support/solutions/articles/65000168651-what-is-the-existential-deposit-
     Polkadot deletes your account if less than 1 DOT
     */
    static let defaultExistentialDeposit: BigInt = 10_000_000_000 // 1 DOT

    static func getPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        guard keysignPayload.coin.chain == .polkadot else {
            throw HelperError.runtimeError("coin is not DOT")
        }

        guard case .Polkadot(
            let recentBlockHash,
            let nonce,
            let currentBlockNumber,
            let specVersion,
            let transactionVersion,
            let genesisHash,
            _
        ) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("getPreSignedInputData fail to get DOT transaction information from RPC")
        }

        guard let toAddress = AnyAddress(string: keysignPayload.toAddress, coin: .polkadot) else {
            throw HelperError.runtimeError("fail to get to address")
        }

        let genesisHashData = Data(hexString: genesisHash)!
        let input = PolkadotSigningInput.with {
            $0.genesisHash = genesisHashData
            $0.blockHash = Data(hexString: recentBlockHash)!
            $0.nonce = nonce
            $0.specVersion = specVersion
            $0.network = CoinType.polkadot.ss58Prefix
            $0.transactionVersion = transactionVersion
            $0.era = PolkadotEra.with {
                $0.blockNumber = UInt64(currentBlockNumber)
                $0.period = 64
            }

            // After Asset Hub update, even native DOT transfers use assetTransfer
            // with assetID 0 and feeAssetID 0 for native DOT
            // When asset_id is 0, WalletCore encodes it as TransferAllowDeath (Balances.transfer)
            // So we need Balances pallet call indices, not Assets pallet
            // For Asset Hub, Balances pallet is typically module 10, method 0 (transfer_allow_death)
            $0.balanceCall.assetTransfer = PolkadotBalance.AssetTransfer.with {
                // ZERO ASSET ID AND FEE ASSET ID ARE FOR DOT (native token)
                $0.assetID = 0
                $0.feeAssetID = 0
                $0.toAddress = toAddress.description
                $0.value = keysignPayload.toAmount.magnitude.serialize()
                // Set call indices for Asset Hub Balances.transfer_allow_death
                // Module 10 (Balances), Method 0 (transfer_allow_death)
                $0.callIndices = PolkadotCallIndices.with {
                    $0.custom = PolkadotCustomCallIndices.with {
                        $0.moduleIndex = 10  // Balances pallet on Asset Hub
                        $0.methodIndex = 0   // transfer_allow_death method
                    }
                }
            }
        }

        let serializedData = try input.serializedData()
        return serializedData
    }

    static func getPreSignedImageHash(keysignPayload: KeysignPayload) throws -> [String] {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let hashes = TransactionCompiler.preImageHashes(coinType: .polkadot, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        if !preSigningOutput.errorMessage.isEmpty {
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }
        return [preSigningOutput.data.hexString]
    }

    static func getZeroSignedTransaction(keysignPayload: KeysignPayload) throws -> String {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)

        let hashes = TransactionCompiler.preImageHashes(coinType: .polkadot, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        if !preSigningOutput.errorMessage.isEmpty {
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }

        let dummyPrivateKey = PrivateKey()
        let dummyPublicKey = dummyPrivateKey.getPublicKeyEd25519()
        let publicKeyData = dummyPublicKey.data
        print("[Polkadot] getZeroSignedTransaction: Using DUMMY public key for fee calculation: \(publicKeyData.hexString.prefix(16))...")

        let allSignatures = DataVector()
        let publicKeys = DataVector()
        let zeroSignature = Data(repeating: 0, count: 64)
        allSignatures.add(data: zeroSignature)
        publicKeys.add(data: publicKeyData)

        let compiledWithSignature = TransactionCompiler.compileWithSignatures(
            coinType: .polkadot,
            txInputData: inputData,
            signatures: allSignatures,
            publicKeys: publicKeys
        )

        let output = try PolkadotSigningOutput(serializedBytes: compiledWithSignature)
        if !output.errorMessage.isEmpty {
            throw HelperError.runtimeError(output.errorMessage)
        }

        return output.encoded.hexString
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
        let hashes = TransactionCompiler.preImageHashes(coinType: .polkadot, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        let allSignatures = DataVector()
        let publicKeys = DataVector()
        let signatureProvider = SignatureProvider(signatures: signatures)
        let signature = signatureProvider.getSignature(preHash: preSigningOutput.data)
        guard publicKey.verify(signature: signature, message: preSigningOutput.data) else {
            throw HelperError.runtimeError("fail to verify signature")
        }

        allSignatures.add(data: signature)
        publicKeys.add(data: pubkeyData)
        let compileWithSignature = TransactionCompiler.compileWithSignatures(coinType: .polkadot,
                                                                             txInputData: inputData,
                                                                             signatures: allSignatures,
                                                                             publicKeys: publicKeys)
        let output = try PolkadotSigningOutput(serializedBytes: compileWithSignature)
        let transactionHash = Hash.blake2b(data: output.encoded, size: 32).toHexString()
        let result = SignedTransactionResult(rawTransaction: output.encoded.hexString,
                                             transactionHash: transactionHash)
        return result
    }
}
