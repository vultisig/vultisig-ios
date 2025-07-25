//
//  SolanaSwaps.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 17.01.2025.
//

import Foundation
import WalletCore
import Tss

class SolanaSwaps {
    
    let vaultHexPubKey: String
    
    init(vaultHexPubKey: String) {
        self.vaultHexPubKey = vaultHexPubKey
    }
    
    func getPreSignedImageHash(
        swapPayload: OneInchSwapPayload,
        keysignPayload: KeysignPayload
    ) throws -> [String] {
        let inputData = try getPreSignedInputData(quote: swapPayload.quote, keysignPayload: keysignPayload)
        let imageHash = try SolanaHelper.getPreSignedImageHash(inputData: inputData)
        return imageHash
    }
    
    func getSignedTransaction(
        swapPayload: OneInchSwapPayload,
        keysignPayload: KeysignPayload,
        signatures: [String: TssKeysignResponse]
    ) throws -> SignedTransactionResult {
        let inputData = try getPreSignedInputData(quote: swapPayload.quote, keysignPayload: keysignPayload)
        let result = try SolanaHelper.getSignedTransaction(
            vaultHexPubKey: vaultHexPubKey,
            inputData: inputData,
            signatures: signatures
        )
        return result
    }
    
    private func getPreSignedInputData(
        quote: OneInchQuote,
        keysignPayload: KeysignPayload
    ) throws -> Data {
        
        guard case .Solana(let recentBlockHash, _, _, _, _) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get Solana chain specific")
        }
        
        guard keysignPayload.coin.chain == .solana else {
            throw HelperError.runtimeError("Chain is not Solana")
        }
        
        let updatedTxData = Data(base64Encoded: quote.tx.data) ?? Data()
        let decodedData = TransactionDecoder.decode(coinType: .solana, encodedTx: updatedTxData)
        var decodedOutput = try SolanaDecodingTransactionOutput(serializedBytes: decodedData)
        
        switch decodedOutput.transaction.message {
        case .legacy(var legacyMessage):
            legacyMessage.recentBlockhash = recentBlockHash
            decodedOutput.transaction.message = .legacy(legacyMessage)
        case .v0(var v0Message):
            v0Message.recentBlockhash = recentBlockHash
            decodedOutput.transaction.message = .v0(v0Message)
        default:
            throw HelperError.runtimeError("Unsupported transaction message type")
        }
        
        let input = SolanaSigningInput.with {
            $0.rawMessage = decodedOutput.transaction
        }
        
        return try input.serializedData()
    }
    
}
