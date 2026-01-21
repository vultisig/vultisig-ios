//
//  CustomMessagePayload.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 29.11.2024.
//

import Foundation
import WalletCore

struct CustomMessagePayload: Codable, Hashable {
    let method: String
    let message: String
    let vaultPublicKeyECDSA: String
    let vaultLocalPartyID: String
    let chain: String

    /// Decoded human-readable version of the message (populated asynchronously)
    var decodedMessage: String? = nil

    var keysignMessages: [String] {
        let data: Data

        if message.starts(with: "0x") {
            data = Data(hex: message)
        } else {
            data = Data(message.utf8)
        }

        // For Ethereum personal_sign, use keccak256 hash
        // For Solana sign_message, use the message directly without hashing
        if method == "personal_sign" || (method != "sign_message" && chain.lowercased() != "solana") {
            let hash = data.sha3(.keccak256)
            return [hash.hexString]
        } else if method == "eth_signTypedData_v4" {
            // Handle eth_signTypedData_v4 (EIP-712)
            return keysignMessagesForTypedData()
        } else {
            // For Solana and other chains that don't use keccak256, use the message directly
            return [data.hexString]
        }
    }

    /// Handles EIP-712 typed data signing
    private func keysignMessagesForTypedData() -> [String] {
        // Use wallet-core's EthereumAbi.encodeTyped to compute the EIP-712 hash
        // This handles all edge cases: BigInt, arrays, nested structs, etc.
        let hash = EthereumAbi.encodeTyped(messageJson: message)

        // Return hex string without 0x prefix (matching the Windows implementation)
        return [hash.hexString.stripHexPrefix()]
    }
}
