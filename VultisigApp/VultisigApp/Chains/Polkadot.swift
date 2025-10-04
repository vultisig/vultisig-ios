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
    
    static func calculateDynamicFee(fromAddress: String, toAddress: String, amount: BigInt) async throws -> BigInt {
        let keysignPayload = try await buildPolkadotKeysignPayload(
            fromAddress: fromAddress,
            toAddress: toAddress,
            amount: amount
        )
        
        let serializedTransaction = try getZeroSignedTransaction(keysignPayload: keysignPayload)
        let partialFee = try await PolkadotService.shared.getPartialFee(serializedTransaction: serializedTransaction)
        
        return partialFee
    }
    
    static func calculateDynamicFee(for tx: SendTransaction) async throws -> BigInt {
        guard tx.coin.chain == .polkadot else {
            throw HelperError.runtimeError("Transaction is not for Polkadot")
        }
        
        return try await calculateDynamicFee(
            fromAddress: tx.coin.address,
            toAddress: tx.toAddress,
            amount: tx.amountInRaw
        )
    }
    
    private static func buildPolkadotKeysignPayload(fromAddress: String, toAddress: String, amount: BigInt) async throws -> KeysignPayload {
        let gasInfo = try await PolkadotService.shared.getGasInfo(fromAddress: fromAddress)
        
        guard let polkadotCoin = TokensStore.TokenSelectionAssets.first(where: { $0.chain == .polkadot && $0.isNativeToken }) else {
            throw HelperError.runtimeError("Polkadot coin not found")
        }
        
        let coin = Coin(asset: polkadotCoin, address: fromAddress, hexPublicKey: "")
        
        return KeysignPayload(
            coin: coin,
            toAddress: toAddress,
            toAmount: amount,
            chainSpecific: .Polkadot(
                recentBlockHash: gasInfo.recentBlockHash,
                nonce: UInt64(gasInfo.nonce),
                currentBlockNumber: gasInfo.currentBlockNumber,
                specVersion: gasInfo.specVersion,
                transactionVersion: gasInfo.transactionVersion,
                genesisHash: gasInfo.genesisHash
            ),
            utxos: [],
            memo: nil,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "",
            vaultLocalPartyID: "",
            libType: "",
            wasmExecuteContractPayload: nil,
            skipBroadcast: false
        )
    }
    
    static func getPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        guard keysignPayload.coin.chain == .polkadot else {
            throw HelperError.runtimeError("coin is not DOT")
        }
        
        guard case .Polkadot(let recentBlockHash, let nonce, let currentBlockNumber, let specVersion, let transactionVersion, let genesisHash, _) = keysignPayload.chainSpecific else {
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
            $0.balanceCall.transfer = PolkadotBalance.Transfer.with {
                $0.toAddress = toAddress.description
                $0.value = keysignPayload.toAmount.magnitude.serialize()
                if let memo = keysignPayload.memo {
                    $0.memo = memo
                }
            }
        }

        return try input.serializedData()
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
        let dummyPrivateKey = PrivateKey()
        let dummyPublicKey = dummyPrivateKey.getPublicKeyEd25519()
        
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        
        let allSignatures = DataVector()
        let publicKeys = DataVector()
        
        let dummySignature = Data(repeating: 0, count: 64)
        allSignatures.add(data: dummySignature)
        publicKeys.add(data: dummyPublicKey.data)
        
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
    
    static func getSignedTransaction(vaultHexPubKey: String,
                                     keysignPayload: KeysignPayload,
                                     signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult
    {
        guard let pubkeyData = Data(hexString: vaultHexPubKey) else {
            throw HelperError.runtimeError("public key \(vaultHexPubKey) is invalid")
        }
        guard let publicKey = PublicKey(data: pubkeyData, type: .ed25519) else {
            throw HelperError.runtimeError("public key \(vaultHexPubKey) is invalid")
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
