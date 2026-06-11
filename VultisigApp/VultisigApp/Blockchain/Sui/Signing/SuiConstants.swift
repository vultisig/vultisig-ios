//
//  SuiConstants.swift
//  VultisigApp
//
//  Created by Vultisig on current date.
//

import Foundation

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

    /// Collapses a package-address segment to `0x` + hex with leading zeros
    /// stripped, so `0x0000…0002` and `0x2` compare equal.
    private static func normalizeAddress(_ address: String) -> String {
        let hex = address.hasPrefix("0x") ? String(address.dropFirst(2)) : address
        let trimmed = String(hex.drop { $0 == "0" })
        return "0x" + (trimmed.isEmpty ? "0" : trimmed)
    }
}
