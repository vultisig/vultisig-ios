//
//  ValidatorBech32Preflight.swift
//  VultisigApp
//
//  Sanity-checks a Cosmos validator operator address (`terravaloper1…`)
//  before the MPC ceremony spends a signing round on a tx the chain will
//  reject post-broadcast. Mirrors the agent-app `requireValoper(...)`
//  guard at `vultiagent-app/src/services/cosmosTx.ts:1110-1140`.
//
//  Two checks:
//
//    1. `AnyAddress.isValidBech32(string:coin:hrp:)` — WalletCore's
//       bech32 charset + checksum + HRP-match validator. Same call site
//       `AddressService` uses for THORChain / Maya / qBTC.
//
//    2. Decoded payload length is exactly 20 bytes (Cosmos AccAddress).
//       WalletCore validates the bech32 envelope but does NOT enforce
//       payload length when a custom HRP is supplied — a 32-byte
//       consensus-pubkey (`*valconspub1…`) with the valoper HRP would
//       otherwise slip past the call above.
//

import Foundation
import WalletCore

enum ValidatorBech32Preflight {

    enum ValidatorBech32Error: Error, LocalizedError, Equatable {
        case empty
        case badEncoding

        var errorDescription: String? {
            switch self {
            case .empty:
                return "validatorBech32ErrorEmpty".localized
            case .badEncoding:
                return "validatorBech32ErrorBadEncoding".localized
            }
        }
    }

    /// Cosmos AccAddress / ValAddress payload length (`ripemd160(sha256(pubkey))`).
    private static let expectedPayloadLength = 20

    static func validate(_ address: String, for chain: Chain) throws {
        guard !address.isEmpty else { throw ValidatorBech32Error.empty }

        let expectedHrp = try CosmosStakingConfig.valoperHrp(for: chain)
        guard AnyAddress.isValidBech32(
            string: address,
            coin: chain.coinType,
            hrp: expectedHrp
        ) else {
            throw ValidatorBech32Error.badEncoding
        }

        guard decodedPayloadLength(address) == expectedPayloadLength else {
            throw ValidatorBech32Error.badEncoding
        }
    }

    /// Number of decoded payload bytes in a bech32 string. Counts data
    /// symbols (after the `1` separator) minus the 6-symbol checksum,
    /// then converts 5-bit → 8-bit. Returns `nil` for inputs without a
    /// separator; WalletCore's `isValidBech32` already rejects those
    /// upstream, so this stays focused on the length arithmetic.
    private static func decodedPayloadLength(_ address: String) -> Int? {
        let lowered = address.lowercased()
        guard let separator = lowered.lastIndex(of: "1") else { return nil }
        let dataPart = lowered[lowered.index(after: separator)...]
        guard dataPart.count >= 6 else { return nil }
        let payload5BitCount = dataPart.count - 6
        return (payload5BitCount * 5) / 8
    }
}
