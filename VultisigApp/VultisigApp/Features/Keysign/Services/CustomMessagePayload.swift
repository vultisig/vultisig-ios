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

        if chain.lowercased() == "cardano" {
            // CIP-30 dApp signing (signTx / signData) — the Windows extension
            // pre-computes the Blake2b-256 of the tx body (signTx) or the COSE
            // Sig_structure bytes (signData) and ships them as the message.
            // Sign verbatim; mirrors getCustomMessageHex.ts in vultisig-windows.
            // Runs first because the Cardano branch is method-independent: a
            // misrouted method (e.g. eth_signTypedData_v4) must not flip us
            // into the EIP-712 path for a Cardano payload.
            return [data.hexString]
        } else if method == "eth_signTypedData_v4" {
            // Handle eth_signTypedData_v4 (EIP-712)
            return keysignMessagesForTypedData()
        } else if isCosmosFamily {
            // Cosmos-family chains (incl. THORChain/Maya) sign the sha256 of the
            // message (Keplr ADR-36 signArbitrary over the StdSignDoc bytes).
            // keccak256 here diverges from the md5 message-ID the initiator
            // derives, so cross-platform co-signing 404s. Mirrors
            // getCustomMessageHex.ts in vultisig-windows and vultisig-android.
            let hash = data.sha256()
            return [hash.hexString]
        } else if method == "sign_message" && chain.lowercased() == "tron" {
            // TRON: message has TIP-191/legacy header prefix from extension, hash with keccak256
            let hash = data.sha3(.keccak256)
            return [hash.hexString]
        } else if method == "personal_sign" || (method != "sign_message" && chain.lowercased() != "solana") {
            // For Ethereum personal_sign, use keccak256 hash
            // For Solana sign_message, use the message directly without hashing
            let hash = data.sha3(.keccak256)
            return [hash.hexString]
        } else {
            // For Solana and other chains that don't use keccak256, use the message directly
            return [data.hexString]
        }
    }

    /// Whether `chain` is a Cosmos-family chain (Cosmos SDK or THORChain/Maya),
    /// which sign the sha256 of the custom message rather than keccak256.
    private var isCosmosFamily: Bool {
        guard let resolved = Chain.allCases.first(where: {
            $0.name.caseInsensitiveCompare(chain) == .orderedSame
        }) else {
            return false
        }
        switch resolved.chainType {
        case .Cosmos, .THORChain:
            return true
        default:
            return false
        }
    }

    /// Handles EIP-712 typed data signing
    private func keysignMessagesForTypedData() -> [String] {
        // Use wallet-core's EthereumAbi.encodeTyped to compute the EIP-712 hash
        // This handles all edge cases: BigInt, arrays, nested structs, etc.
        let hash = EthereumAbi.encodeTyped(messageJson: message)
        let parsedHash = hash.hexString.stripHexPrefix()

        // Return hex string without 0x prefix (matching the Windows implementation)
        return [parsedHash]
    }
}
