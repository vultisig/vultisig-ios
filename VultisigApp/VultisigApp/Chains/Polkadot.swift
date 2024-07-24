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
     https://polkadot.network/blog/polkadot_q4_update_data
     Average daily transaction fees hovered close to 0.02 DOT for all of December. The chart above features data supplied by DotLake, a data platform reflecting activity on Polkadot and its ecosystem, and maintained by engineers and analysts at Parity Technologies.
    */
    static let defaultFeeInPlancks: BigInt = 250_000_000
    
    /*
     https://support.polkadot.network/support/solutions/articles/65000168651-what-is-the-existential-deposit-
     Polkadot deletes your account if less than 1 DOT
     */
    static let defaultExistentialDeposit: BigInt = 10_000_000_000 // 1 DOT
    
    static func getPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        guard keysignPayload.coin.chain == .polkadot else {
            throw HelperError.runtimeError("coin is not DOT")
        }
        
        guard case .Polkadot(let recentBlockHash, let nonce, let currentBlockNumber, let specVersion, let transactionVersion, let genesisHash) = keysignPayload.chainSpecific else {
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
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
        if !preSigningOutput.errorMessage.isEmpty {
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }
        return [preSigningOutput.data.hexString]
    }
    
    static func getSignedTransaction(vaultHexPubKey: String,
                                     vaultHexChainCode: String,
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
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
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
        let output = try PolkadotSigningOutput(serializedData: compileWithSignature)
        let transactionHash = Hash.blake2b(data: output.encoded, size: 32).toHexString()
        let result = SignedTransactionResult(rawTransaction: output.encoded.hexString,
                                             transactionHash: transactionHash)
        return result
    }
}
