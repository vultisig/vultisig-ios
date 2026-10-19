//
//  CustomMessagePayload.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 29.11.2024.
//

import Foundation
import WalletCore

enum CustomMessagePayloadError: LocalizedError, Equatable {
    case unsupportedChain(String)
    case unsupportedEVMFormat

    var errorDescription: String? {
        switch self {
        case let .unsupportedChain(chain):
            return "Custom-message signing is unavailable for \(chain)."
        case .unsupportedEVMFormat:
            return "unsupportedEVMCustomMessageFormat".localized
        }
    }
}

struct CustomMessagePayload: Codable, Hashable {
    let method: String
    let message: String
    let vaultPublicKeyECDSA: String
    let vaultLocalPartyID: String
    let chain: String

    /// Decoded human-readable version of the message (populated asynchronously)
    var decodedMessage: String? = nil

    /// Identity of the requesting dApp. Display-only: it never feeds
    /// `keysignMessages`, so co-signers that predate the field derive the
    /// same digest.
    var dappMetadata: DAppMetadata? = nil

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
        } else if chain.lowercased() == "ripple" {
            // XRPL off-chain message signing (GemWallet signMessage /
            // ripple-keypairs): the signed digest is SHA-512-half — the first
            // 32 bytes of SHA-512 — of the message bytes. Mirrors the `ripple`
            // branch of getCustomMessageHex.ts in vultisig-windows
            // (`sha512(bytes).slice(0, 32)`), rendered as lowercase hex with no
            // 0x prefix. Note this is the bare SHA-512-half of the message: the
            // `TXN\0` prefix + uppercasing that Ripple.swift applies belong to
            // the transaction-ID path, not here. Placed before the method
            // branches, like Cardano, so a misrouted method can't pull an XRPL
            // payload into the keccak/EIP-712 path.
            let digest = Data(Hash.sha512(data: data).prefix(32))
            return [digest.hexString]
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

    /// Resolves the chain used for key derivation while refusing known retired chains.
    /// Unknown names retain the historical Ethereum fallback used by extension payloads.
    func resolveSigningChain() throws -> Chain {
        guard let resolved = Chain.allCases.first(where: {
            $0.name.caseInsensitiveCompare(chain) == .orderedSame
        }) else {
            return .ethereum
        }
        guard resolved.isSupported else {
            throw CustomMessagePayloadError.unsupportedChain(resolved.name)
        }
        return resolved
    }

    /// EVM custom messages are signed as keccak256 of the raw bytes, which only has a
    /// message-signing domain for an EIP-191 envelope or EIP-712 typed data. Everything
    /// else is refused so the vault key never signs an arbitrary 32-byte digest.
    /// Unknown chain names fall back to Ethereum, as in `resolveSigningChain()`.
    func validateEVMSignable() throws {
        let resolved = Chain.allCases.first { $0.name.caseInsensitiveCompare(chain) == .orderedSame } ?? .ethereum
        guard resolved.chainType == .EVM else { return }
        if method == "eth_signTypedData_v4" { return }
        guard method == "personal_sign", hasEIP191Envelope else {
            throw CustomMessagePayloadError.unsupportedEVMFormat
        }
    }

    /// `\x19Ethereum Signed Message:\n`, a decimal length, then exactly that many bytes.
    private var hasEIP191Envelope: Bool {
        let bytes = [UInt8](message.starts(with: "0x") ? Data(hex: message) : Data(message.utf8))
        let prefix = [UInt8]("\u{19}Ethereum Signed Message:\n".utf8)
        guard bytes.starts(with: prefix) else { return false }
        let rest = bytes.dropFirst(prefix.count)
        let digits = rest.prefix(while: { $0 >= 0x30 && $0 <= 0x39 })
        // The length's digits are followed by message bytes that may themselves be digits,
        // so accept any split whose declared length matches the bytes after it.
        return digits.indices.contains { end in
            let count = end - digits.startIndex + 1
            return String(bytes: digits.prefix(count), encoding: .utf8).flatMap({ Int($0) }) == rest.count - count
        }
    }

    /// Whether `chain` is a Cosmos-family chain (Cosmos SDK or THORChain/Maya),
    /// which sign the sha256 of the custom message rather than keccak256. Compatibility
    /// identities remain classified here so historical payloads decode deterministically;
    /// `resolveSigningChain()` rejects them before a signing ceremony starts.
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
