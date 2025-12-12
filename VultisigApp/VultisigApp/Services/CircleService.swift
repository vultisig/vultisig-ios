//
//  CircleService.swift
//  VultisigApp
//
//  Created by Antigravity on 2025-12-11.
//

import Foundation
import WalletCore
import BigInt

enum CircleServiceError: Error {
    case invalidDetails
    case keysignError(String)
}

struct CircleService {
    static let shared = CircleService()
    
    private init() {}
    
    // MARK: - Payload Generation
    
    /// Generates the payload required for keysign
    /// - Parameters:
    ///   - encryptionKeyHex: The encryption hex key
    ///   - vault: The vault instance
    ///   - toAddress: Destination address (for withdraw/deposit etc.)
    ///   - amount: Amount to transact
    ///   - memo: Optional memo
    ///   - fee: Gas fee
    ///   - transactionType: Type of transaction (withdraw, claim, etc.)
    ///   - chainSpecific: Chain specific parameters
    func getKeysignPayload(
        encryptionKeyHex: String,
        vault: Vault,
        toAddress: String,
        amount: BigInt,
        memo: String?,
        fee: BigInt,
        chainSpecific: BlockChainSpecific
    ) async throws -> KeysignMessage {
        
        print("CircleService: getKeysignPayload called")
        print("CircleService: Inputs - To: \(toAddress), Amount: \(amount), Fee: \(fee)")

        guard let coin = vault.coins.first(where: { $0.chain == .ethereum && $0.isNativeToken }) else {
            print("CircleService: Error - ETH native token not found in vault")
            throw CircleServiceError.invalidDetails
        }
        print("CircleService: Using coin: \(coin.ticker)")
        
        // MCSA uses Ethereum chain (Circle uses Ethereum Mainnet)
        // We reuse Ethereum logic but with specific contract calls if needed
        let keyType = coin.chain.signingKeyType
        
        // Basic Payload structure - this mirrors EVM payload generation
        // For MCSA "execute" calls, the `toAddress` is the MCSA contract itself, 
        // and data contains the encoded function call.
        // However, if we are just signing a message or a specific typed data, this changes.
        // Based on Issue #3481, we sign transactions via TSS.
        
        // TODO: This logic needs to be verified against specific MCSA `execute` function signature.
        // For now, generating a standard EVM keysign message.
        
        let toParam = toAddress
        let amountParam = amount
        
        // Construct standard keysign payload
        let keysignPayload = KeysignPayload(
            coin: coin,
            toAddress: toAddress,
            toAmount: amount, // Amount 0 for the execution call itself (ETH transferred), usually 0 for calling a contract unless sending ETH
            chainSpecific: chainSpecific,
            utxos: [],
            memo: nil,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: vault.pubKeyECDSA,
            vaultLocalPartyID: vault.localPartyID,
            libType: (vault.libType ?? .GG20) == .DKLS ? "dkls" : "gg20",
            wasmExecuteContractPayload: nil,
            skipBroadcast: false
        )
        
        print("CircleService: KeysignPayload constructed. Chain: \(coin.chain.name), To: \(keysignPayload.toAddress), Amount: \(keysignPayload.toAmount)")
        
        return KeysignMessage(
            sessionID: UUID().uuidString,
            serviceName: "Circle",
            payload: keysignPayload,
            customMessagePayload: nil,
            encryptionKeyHex: encryptionKeyHex,
            useVultisigRelay: false,
            payloadID: UUID().uuidString
        )
    }
}
