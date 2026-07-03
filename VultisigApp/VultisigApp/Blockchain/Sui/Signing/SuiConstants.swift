//
//  SuiConstants.swift
//  VultisigApp
//
//  Created by Vultisig on current date.
//

import Foundation
import BigInt

/// Constants for SUI chain
enum SuiConstants {
    /// USDC contract address on SUI chain
    static let usdcAddress = "0xdba34672e30cb065b1f93e3ab55318768fd6fef66c15942c9f7cb846e2f900e7::usdc::USDC"

    /// Default decimals for SUI native token
    static let defaultDecimals = 9

    /// USDC decimals on SUI chain
    static let usdcDecimals = 6

    /// Canonical fully-qualified type of the native SUI coin (short address form).
    static let nativeCoinType = "0x2::sui::SUI"
}

/// Exact, normalization-aware matching for SUI coin-object types.
///
/// SUI coin objects are identified by a fully-qualified `address::module::struct`
/// type. The first segment (the package address) can appear in either short form
/// (`0x2`) or the 64-hex-digit long form the node returns from
/// `suix_getAllCoins` (`0x0000…0002`). Matching coin objects by ticker substring
/// is wrong: it cannot distinguish `0x2::sui::SUI` from `0x…::xsui::XSUI`, and it
/// fails for tokens whose on-chain symbol differs from their display ticker
/// (e.g. Wormhole-bridged `…::coin::COIN`). This enum compares the full type
/// after normalizing only the address segment.
enum SuiCoinType {

    /// Normalizes a fully-qualified coin type for exact comparison: lowercases the
    /// whole string and collapses the package-address segment to a canonical
    /// `0x`-prefixed, leading-zero-stripped form. The module/struct segments are
    /// compared case-insensitively but otherwise left intact.
    static func normalize(_ coinType: String) -> String {
        let lowered = coinType.lowercased()
        let segments = lowered.split(separator: ":", omittingEmptySubsequences: false)
        // Expected form is `address::module::struct` -> 5 segments around the two `::`.
        guard let addressSegment = segments.first, !addressSegment.isEmpty else {
            return lowered
        }
        let normalizedAddress = normalizeAddress(String(addressSegment))
        let remainder = lowered.dropFirst(addressSegment.count)
        return normalizedAddress + remainder
    }

    /// Returns whether two fully-qualified coin types refer to the same coin,
    /// independent of package-address form (short `0x2` vs long `0x00…02`).
    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        return normalize(lhs) == normalize(rhs)
    }

    /// The fully-qualified type a `Coin` record represents: its `contractAddress`
    /// for tokens, or the canonical native SUI type when the record is native
    /// (native SUI carries an empty `contractAddress`).
    static func expectedType(isNativeToken: Bool, contractAddress: String) -> String {
        if isNativeToken || contractAddress.isEmpty {
            return SuiConstants.nativeCoinType
        }
        return contractAddress
    }

    /// Whether the given coin-object type is the native SUI coin.
    static func isNative(_ coinType: String) -> Bool {
        return matches(coinType, SuiConstants.nativeCoinType)
    }

    /// Filters a set of owned coin objects down to exactly what a SUI send
    /// serializes into the keysign payload: the native SUI objects (always
    /// needed — they pay gas, and for a native send they are also the inputs)
    /// plus, for a token send, the objects of the token being sent. Every other
    /// owned object (unrelated memecoins / LSTs) is dropped so the payload — and
    /// therefore the pairing QR and TSS relay payload — stays small.
    ///
    /// `getPreSignedInputData` performs the same selection on this set, so the
    /// filtered output is exactly the inputs the signer consumes.
    static func payloadCoins(
        _ coins: [[String: String]],
        isNativeToken: Bool,
        contractAddress: String
    ) -> [[String: String]] {
        let tokenType = expectedType(isNativeToken: isNativeToken, contractAddress: contractAddress)
        return coins.filter { coin in
            let coinType = coin["coinType"] ?? .empty
            return isNative(coinType) || matches(coinType, tokenType)
        }
    }

    /// Selects the native SUI coin object that pays gas for a token
    /// (non-native) send. WalletCore's `Sui.Pay` message carries a *single*
    /// `gas` object (unlike `PaySui`, whose whole input set is gas-smashed and
    /// therefore merged), so the choice matters: picking an arbitrary object —
    /// e.g. the first one the RPC happened to return — fails when that object's
    /// balance can't cover the budget, even though the wallet holds plenty of
    /// SUI across other objects.
    ///
    /// Mirrors the Android client: choose the *smallest* native SUI object whose
    /// balance already covers `gasBudget`, so gas is guaranteed payable while the
    /// larger objects stay available. When no single object covers the budget,
    /// fall back to the largest object (best effort — strictly better than an
    /// arbitrary pick). Returns `nil` only when the wallet holds no native SUI
    /// object at all.
    static func selectGasObject(_ coins: [[String: String]], gasBudget: BigInt) -> [String: String]? {
        let suiObjects = coins.filter { isNative($0["coinType"] ?? .empty) }
        guard !suiObjects.isEmpty else { return nil }

        let covering = suiObjects.filter { balance(of: $0) >= gasBudget }
        if let smallestCovering = covering.min(by: { balance(of: $0) < balance(of: $1) }) {
            return smallestCovering
        }
        return suiObjects.max(by: { balance(of: $0) < balance(of: $1) })
    }

    /// Parses a coin object's `balance` field (base-unit MIST) as `BigInt`,
    /// treating a missing or unparseable value as zero.
    static func balance(of coin: [String: String]) -> BigInt {
        guard let raw = coin["balance"], let value = BigInt(raw) else { return .zero }
        return value
    }

    /// Collapses a package-address segment to `0x` + hex with leading zeros
    /// stripped, so `0x0000…0002` and `0x2` compare equal.
    private static func normalizeAddress(_ address: String) -> String {
        let hex = address.hasPrefix("0x") ? String(address.dropFirst(2)) : address
        let trimmed = String(hex.drop { $0 == "0" })
        return "0x" + (trimmed.isEmpty ? "0" : trimmed)
    }
}
