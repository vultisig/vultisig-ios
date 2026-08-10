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

    /// Budget used to price the initial dry-run transaction.
    static let defaultGasBudget = BigInt(3_000_000)

    /// Upper bound on the coin objects a single send may reference. Sui rejects a
    /// transaction whose serialized size exceeds 128 KiB, and a `PaySui` send uses
    /// its entire input set as the gas payment — which Sui caps at 256 objects. A
    /// wallet whose balance is spread across thousands of small objects would, if
    /// every object were referenced, blow past both limits and fail at broadcast
    /// ("serialized transaction size exceeded maximum"). Staying one under the
    /// 256-object gas-payment cap keeps every send safely within both limits.
    static let maxInputCoinObjects = 255

    /// How many of the largest native SUI objects to embed as gas candidates for
    /// a token send. The signer picks one to pay gas; carrying the largest few
    /// (rather than all, or just one) keeps the payload small while guaranteeing a
    /// covering object survives a re-estimated gas budget.
    static let gasCandidateObjectCount = 5

    /// Keep the final payload at least as well funded as the transaction that was
    /// priced during the dry run. A lower refined budget must not remove objects
    /// that were present in the simulated input set.
    static func payloadSelectionGasBudget(for gasBudget: BigInt) -> BigInt {
        max(defaultGasBudget, gasBudget)
    }
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

    /// Normalizes a fully-qualified coin type for exact comparison by collapsing
    /// only the package-address segment to a canonical lowercased,
    /// leading-zero-stripped form. Move module and struct identifiers remain
    /// case-sensitive because `::coin::USDC` and `::coin::usdc` are distinct
    /// types.
    static func normalize(_ coinType: String) -> String {
        guard let separator = coinType.range(of: "::") else {
            return normalizeAddress(coinType)
        }
        let address = String(coinType[..<separator.lowerBound])
        return normalizeAddress(address) + String(coinType[separator.lowerBound...])
    }

    /// The coin type a `0x2::coin::Coin<T>` object holds, in the same spelling
    /// JSON-RPC returned.
    ///
    /// GraphQL's object connection reports the **wrapper** struct, where
    /// `suix_getAllCoins` reported the bare `T`. Two things then have to happen
    /// before the rest of the app sees the string, or the transport swap stops
    /// being invisible:
    ///
    /// 1. **Unwrap.** A wrapper string matches no known coin, so `isNative` and
    ///    `matches` both fail and every native send is misread as a token send.
    /// 2. **Normalize the address.** GraphQL always spells it zero-padded
    ///    (`0x000…002::sui::SUI`) where JSON-RPC returned it stripped
    ///    (`0x2::sui::SUI`). Comparisons tolerate either — that is what
    ///    `normalize` is for — but `SuiService.getAllTokensWithMetadata`
    ///    *persists* this string as a discovered token's `contractAddress`, so
    ///    without stripping, a token discovered after the migration becomes a
    ///    second vault entry differing from the pre-migration one only by
    ///    padding.
    ///
    /// Returns `nil` for anything that is not a generic instantiation, which the
    /// query's type filter already excludes.
    static func unwrap(_ repr: String) -> String? {
        guard let open = repr.firstIndex(of: "<"),
              let close = repr.lastIndex(of: ">"),
              open < close else {
            return nil
        }
        let inner = String(repr[repr.index(after: open)..<close])
        guard !inner.isEmpty else { return nil }
        return normalize(inner)
    }

    /// Returns whether two fully-qualified coin types refer to the same coin,
    /// independent of package-address form (short `0x2` vs long `0x00…02`).
    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        return normalize(lhs) == normalize(rhs)
    }

    /// A lowercase, case-preserving storage key for fiat rates. `Rate` IDs are
    /// lowercased globally, while Move module and struct names are case-sensitive;
    /// encoding the normalized UTF-8 bytes prevents distinct Sui types such as
    /// `::coin::USDC` and `::coin::usdc` from sharing the same cached rate.
    static func rateKey(_ coinType: String) -> String {
        let encodedType = normalize(coinType).utf8
            .map { String(format: "%02x", $0) }
            .joined()
        return "sui-\(encodedType)"
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

    /// The minimal set of coin objects to embed in the keysign payload for a Sui
    /// send — exactly what `getPreSignedInputData` will consume.
    ///
    /// Embedding every matching object on a wallet whose balance is spread across
    /// thousands of objects produces a keysign payload too large to relay — the
    /// co-signer's poll 404s and the initiator's transaction data expires before
    /// signing can start. Bounding the set to the objects the send actually needs
    /// keeps the pairing QR / TSS relay message small.
    ///
    /// Native send: the largest objects covering `amount + gasBudget` (the input
    /// set also pays gas). Token send: the largest token objects covering
    /// `amount`, plus the largest few native SUI objects as gas candidates.
    static func selectPayloadCoins(
        _ coins: [[String: String]],
        isNativeToken: Bool,
        contractAddress: String,
        amount: BigInt,
        gasBudget: BigInt
    ) -> [[String: String]] {
        let nativeObjects = coins.filter { isNative($0["coinType"] ?? .empty) }

        if isNativeToken {
            return selectInputCoins(nativeObjects, covering: amount + gasBudget)
        }

        let tokenType = expectedType(isNativeToken: isNativeToken, contractAddress: contractAddress)
        let tokenObjects = coins.filter {
            let coinType = $0["coinType"] ?? .empty
            return matches(coinType, tokenType) && !isNative(coinType)
        }
        let selectedTokens = selectInputCoins(tokenObjects, covering: amount)
        let gasCandidates = Array(
            nativeObjects
                .sorted { lhs, rhs in
                    let lhsBalance = balance(of: lhs)
                    let rhsBalance = balance(of: rhs)
                    if lhsBalance != rhsBalance { return lhsBalance > rhsBalance }
                    return objectID(of: lhs) < objectID(of: rhs)
                }
                .prefix(SuiConstants.gasCandidateObjectCount)
        )
        return selectedTokens + gasCandidates
    }

    /// Selects the native SUI coin object that pays gas for a token
    /// (non-native) send. WalletCore's `Sui.Pay` message carries a *single*
    /// `gas` object (unlike `PaySui`, whose whole input set is gas-smashed and
    /// therefore merged), so the choice matters: picking an arbitrary object —
    /// e.g. the first one the RPC happened to return — fails when that object's
    /// balance can't cover the budget, even though the wallet holds plenty of
    /// SUI across other objects.
    ///
    /// Mirrors the Android and SDK clients: choose the *smallest* native SUI
    /// object whose balance already covers `gasBudget`, then use `objectID` as the
    /// deterministic tie-break. Returns `nil` when no single object can pay gas.
    static func selectGasObject(_ coins: [[String: String]], gasBudget: BigInt) -> [String: String]? {
        coins
            .filter {
                isNative($0["coinType"] ?? .empty) && balance(of: $0) >= gasBudget
            }
            .min { lhs, rhs in
                let lhsBalance = balance(of: lhs)
                let rhsBalance = balance(of: rhs)
                if lhsBalance != rhsBalance { return lhsBalance < rhsBalance }
                return objectID(of: lhs) < objectID(of: rhs)
            }
    }

    /// Returns whether the selected objects cover the required target.
    static func covers(_ coins: [[String: String]], target: BigInt) -> Bool {
        return coins.reduce(BigInt.zero) { partialResult, coin in
            partialResult + balance(of: coin)
        } >= target
    }

    /// Selects the fewest coin objects (largest balance first) that together
    /// cover `target`, bounded by `maxObjects`.
    ///
    /// Passing every owned object into a send is what produces the "serialized
    /// transaction size exceeded maximum" broadcast failure on wallets whose
    /// balance is scattered across many objects — and, for a native `PaySui`
    /// send, also trips Sui's 256-object gas-payment cap. Taking only the largest
    /// objects needed to fund the send keeps the transaction small while still
    /// merging a scattered balance: for a native send WalletCore/Sui gas-smashes
    /// the selected objects into one spendable coin. `target` is the send amount
    /// plus, for a native send, the gas budget (the native input set also pays
    /// gas); for a token send it is just the token amount.
    ///
    /// Selection is deterministic (balance descending, then `objectID`) so every
    /// co-signing device selects the identical set and signs the identical
    /// transaction. If even `maxObjects` largest objects don't reach `target`,
    /// they are still returned (best effort) — the caller decides how to handle
    /// an under-funded selection.
    static func selectInputCoins(
        _ coins: [[String: String]],
        covering target: BigInt,
        maxObjects: Int = SuiConstants.maxInputCoinObjects
    ) -> [[String: String]] {
        let sorted = coins.sorted { lhs, rhs in
            let lhsBalance = balance(of: lhs)
            let rhsBalance = balance(of: rhs)
            if lhsBalance != rhsBalance { return lhsBalance > rhsBalance }
            return objectID(of: lhs) < objectID(of: rhs)
        }

        var selected: [[String: String]] = []
        var accumulated = BigInt.zero
        for coin in sorted {
            // Always keep at least one object so a zero/near-zero-amount send
            // still has an input; otherwise stop once the target is covered.
            if !selected.isEmpty && accumulated >= target { break }
            if selected.count >= maxObjects { break }
            selected.append(coin)
            accumulated += balance(of: coin)
        }
        return selected
    }

    /// Parses a coin object's `balance` field (base-unit MIST) as `BigInt`,
    /// treating a missing or unparseable value as zero.
    static func balance(of coin: [String: String]) -> BigInt {
        guard let raw = coin["balance"], let value = BigInt(raw) else { return .zero }
        return value
    }

    private static func objectID(of coin: [String: String]) -> String {
        coin["objectID"] ?? .empty
    }

    /// Collapses a package-address segment to `0x` + hex with leading zeros
    /// stripped, so `0x0000…0002` and `0x2` compare equal.
    private static func normalizeAddress(_ address: String) -> String {
        let lowered = address.lowercased()
        let hex = lowered.hasPrefix("0x") ? String(lowered.dropFirst(2)) : lowered
        let trimmed = String(hex.drop { $0 == "0" })
        return "0x" + (trimmed.isEmpty ? "0" : trimmed)
    }
}
