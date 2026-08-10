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
/// (`0x2`) or the 64-hex-digit long form the node returns from the coin-object
/// connection (`0x0000…0002`). Matching coin objects by ticker substring
/// is wrong: it cannot distinguish `0x2::sui::SUI` from `0x…::xsui::XSUI`, and it
/// fails for tokens whose on-chain symbol differs from their display ticker
/// (e.g. Wormhole-bridged `…::coin::COIN`). This enum compares the full type
/// after normalizing only the address segment.
enum SuiCoinType {

    /// Normalizes a fully-qualified coin type for exact comparison by collapsing
    /// every package-address segment to a canonical lowercased,
    /// leading-zero-stripped form. Move module and struct identifiers remain
    /// case-sensitive because `::coin::USDC` and `::coin::usdc` are distinct
    /// types.
    ///
    /// **Every** address, not just the leading one: a generic instantiation such
    /// as `0xabc::pool::LP<0x000…002::sui::SUI, 0xdef::usdc::USDC>` carries
    /// addresses inside its type arguments too. Normalizing only the outer one
    /// leaves the same coin comparing unequal to itself depending on which
    /// endpoint spelled it — and `getAllTokensWithMetadata` persists this string
    /// as a discovered token's `contractAddress`, so the inconsistency becomes a
    /// duplicate vault entry rather than a transient mismatch.
    static func normalize(_ coinType: String) -> String {
        var result = ""
        var segment = ""

        for character in coinType {
            if character == "<" || character == ">" || character == "," || character == " " {
                result += normalizeSegment(segment)
                result.append(character)
                segment = ""
            } else {
                segment.append(character)
            }
        }

        return result + normalizeSegment(segment)
    }

    /// Normalizes the leading address of one `address::module::struct` token.
    ///
    /// A delimiter-free token is only an address if it *looks* like one. Move's
    /// primitives and type constructors — `u64`, `bool`, `vector` — are also
    /// delimiter-free, and running them through `normalizeAddress` invents types
    /// that do not exist (`0xu64`, `0xvector<0xu8>`). Since this value is
    /// persisted as a token's `contractAddress`, a mangled one would never match
    /// the real coin again.
    private static func normalizeSegment(_ segment: String) -> String {
        guard !segment.isEmpty else { return segment }
        guard let separator = segment.range(of: "::") else {
            guard segment.lowercased().hasPrefix("0x") else { return segment }
            return normalizeAddress(segment)
        }
        let address = String(segment[..<separator.lowerBound])
        return normalizeAddress(address) + String(segment[separator.lowerBound...])
    }

    /// The `0x2::coin::Coin` wrapper struct, in canonical form.
    private static let coinWrapperType = "0x2::coin::Coin"

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
    /// 2. **Normalize the addresses.** GraphQL always spells them zero-padded
    ///    (`0x000…002::sui::SUI`) where JSON-RPC returned them stripped
    ///    (`0x2::sui::SUI`). Comparisons tolerate either — that is what
    ///    `normalize` is for — but `SuiService.getAllTokensWithMetadata`
    ///    *persists* this string as a discovered token's `contractAddress`, so
    ///    without stripping, a token discovered after the migration becomes a
    ///    second vault entry differing from the pre-migration one only by
    ///    padding.
    ///
    /// Parsing is strict on purpose. The result is persisted and later compared
    /// against curated catalog entries, so a string this cannot fully account
    /// for must be rejected rather than half-parsed: the wrapper has to be
    /// exactly `0x2::coin::Coin`, the generic argument has to run to the end of
    /// the input, and its angle brackets have to balance. Anything else — a
    /// different wrapper, trailing text, a stray `>` — returns `nil`, and
    /// `classifyNonCoin` then decides whether that is an object we never wanted
    /// or one we failed to read.
    static func unwrap(_ repr: String) -> String? {
        guard let open = repr.firstIndex(of: "<"), repr.hasSuffix(">") else { return nil }

        guard normalize(String(repr[..<open])) == coinWrapperType else { return nil }

        let inner = String(repr[repr.index(after: open)..<repr.index(before: repr.endIndex)])
        guard !inner.isEmpty, hasBalancedBrackets(inner) else { return nil }

        return normalize(inner)
    }

    /// Whether every `<` in `type` is closed, and no `>` appears before its `<`.
    /// Rejects both `LP<A` and `A>B`, either of which would otherwise slice into
    /// a plausible-looking but wrong type.
    private static func hasBalancedBrackets(_ type: String) -> Bool {
        var depth = 0
        for character in type {
            if character == "<" {
                depth += 1
            } else if character == ">" {
                depth -= 1
                if depth < 0 { return false }
            }
        }
        return depth == 0
    }

    /// What to do with a coin-object type that `unwrap` refused.
    enum ForeignTypeVerdict: Equatable {
        /// Definitively a different struct — `TreasuryCap<T>`, `CoinMetadata<T>`.
        /// Not a coin, so dropping it loses nothing.
        case differentStruct
        /// Cannot be accounted for. We do not know what it is, so we cannot say
        /// dropping it is safe.
        case unreadable
    }

    /// Classifies a type string that is not a `0x2::coin::Coin<T>`.
    ///
    /// The distinction is the whole point: skipping a `TreasuryCap` costs
    /// nothing, whereas skipping something we merely failed to parse silently
    /// shrinks a set that funds a transaction. Anything shaped like the coin
    /// wrapper but not successfully unwrapped is therefore `unreadable`, never
    /// `differentStruct` — a truncated `Coin<T>` must not be able to disguise
    /// itself as an object we never wanted.
    static func classifyNonCoin(_ repr: String) -> ForeignTypeVerdict {
        guard hasBalancedBrackets(repr) else { return .unreadable }

        // A generic instantiation has to close at the very end; trailing text
        // means there is more here than we understand.
        if repr.contains("<"), !repr.hasSuffix(">") { return .unreadable }

        let head = String(repr.prefix { $0 != "<" })
        let parts = head.components(separatedBy: "::")
        guard parts.count == 3,
              isHexAddress(parts[0]),
              isMoveIdentifier(parts[1]),
              isMoveIdentifier(parts[2]) else {
            return .unreadable
        }

        // It IS the coin wrapper, and `unwrap` still refused it — an empty type
        // argument, a missing one, or trailing text. That is a broken coin, not
        // a foreign object.
        guard normalize(head) != coinWrapperType else { return .unreadable }

        return .differentStruct
    }

    /// `0x`-prefixed hexadecimal, which every Move package address is.
    private static func isHexAddress(_ segment: String) -> Bool {
        guard segment.lowercased().hasPrefix("0x") else { return false }
        let digits = segment.dropFirst(2)
        return !digits.isEmpty && digits.allSatisfy(\.isHexDigit)
    }

    /// A Move identifier: ASCII alphanumerics and underscores, not starting with
    /// a digit.
    private static func isMoveIdentifier(_ segment: String) -> Bool {
        guard let first = segment.first, first.isLetter || first == "_" else { return false }
        return segment.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
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
