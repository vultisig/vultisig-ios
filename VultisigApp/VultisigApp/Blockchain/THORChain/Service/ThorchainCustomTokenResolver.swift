//
//  ThorchainCustomTokenResolver.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 03/06/2025.
//

import Foundation

/// Resolves a user-typed THORChain token identifier into a ``CoinMeta``.
///
/// THORChain non-RUNE tokens are Cosmos bank denoms (e.g. `thor.lqdy`), discovered
/// via the bank balances endpoint — not the `/thorchain/pools` LP endpoint. The
/// pool endpoint is therefore the wrong gate: a token can exist as a bank denom
/// with no L1 pool. Users reference these tokens in `THOR.{SYMBOL}` pool/display
/// notation, so the custom-token search has to map that shape onto the lowercase
/// bank denom before resolving metadata.
enum ThorchainCustomTokenResolver {

    enum ResolverError: Error, LocalizedError {
        case invalidFormat

        var errorDescription: String? {
            switch self {
            case .invalidFormat:
                return "thorchainCustomTokenInvalidFormat".localized
            }
        }
    }

    /// Normalizes a user-typed THORChain token identifier into its lowercase bank
    /// denom. Accepts `THOR.LQDY`, `thor.lqdy`, or a bare `LQDY` symbol; all map to
    /// `thor.lqdy`. Returns `nil` when the input doesn't describe a valid symbol.
    ///
    /// - Parameter input: Raw user input.
    /// - Returns: The lowercase bank denom (`thor.<symbol>`), or `nil` if invalid.
    static func normalizeDenom(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let symbol: String
        if let dotIndex = trimmed.firstIndex(of: ".") {
            let prefix = trimmed[trimmed.startIndex..<dotIndex].lowercased()
            guard prefix == "thor" else { return nil }
            symbol = String(trimmed[trimmed.index(after: dotIndex)...])
        } else {
            // A bare input without a dot must be a symbol, not a pasted `thor1…`
            // bech32 account address; reject the latter so it can't be turned into
            // a bogus `thor.thor1…` denom.
            guard !trimmed.lowercased().hasPrefix("thor1") else { return nil }
            symbol = trimmed
        }

        guard isValidSymbol(symbol) else { return nil }
        return "thor.\(symbol.lowercased())"
    }

    /// Extracts the bare symbol (uppercased) from a user-typed identifier, e.g.
    /// `THOR.LQDY` / `thor.lqdy` / `LQDY` → `LQDY`. Returns `nil` when invalid.
    static func symbol(from input: String) -> String? {
        guard let denom = normalizeDenom(from: input) else { return nil }
        return String(denom.dropFirst("thor.".count)).uppercased()
    }

    /// Validates that the input is a well-formed THORChain custom-token identifier
    /// (`THOR.{SYMBOL}`, `thor.{symbol}`, or a bare `{SYMBOL}`), without hitting the
    /// network. Used to gate the custom-token search before any lookup.
    static func isValidInput(_ input: String) -> Bool {
        normalizeDenom(from: input) != nil
    }

    /// A symbol is the token ticker that follows the `thor.` prefix (e.g. `lqdy`,
    /// `rkuji`). It must start with a letter and otherwise be alphanumeric: this
    /// keeps malformed input (spaces, extra dots, punctuation, `0x…`/bech32
    /// addresses) from being treated as a denom and short-circuits a doomed
    /// network lookup.
    private static func isValidSymbol(_ symbol: String) -> Bool {
        guard (1...maxSymbolLength).contains(symbol.count),
              let first = symbol.first, first.isLetter else {
            return false
        }
        return symbol.allSatisfy { $0.isLetter || $0.isNumber }
    }

    /// Generous upper bound on a token symbol's length. The longest curated THOR
    /// token ticker today is five characters (`RKUJI`); the cap mainly stops long
    /// pasted blobs (e.g. addresses) from masquerading as a symbol.
    private static let maxSymbolLength = 12

    /// Resolves a THORChain custom-token identifier to a ``CoinMeta`` via the bank-denom
    /// metadata path, mirroring `ThorchainService.fetchTokens`: it tries the on-chain
    /// `denoms_metadata` first, then falls back to `THORChainTokenMetadataFactory`. A
    /// curated ``TokensStore`` entry (matched by denom, then ticker) is preferred for the
    /// logo and `priceProviderId` so known tokens render their real art.
    ///
    /// - Parameter input: Raw user input (`THOR.LQDY`, `thor.lqdy`, or `LQDY`).
    /// - Returns: A `CoinMeta` for `chain: .thorChain`.
    /// - Throws: ``ResolverError/invalidFormat`` when the input is malformed.
    static func resolve(input: String, service: ThorchainService = .shared) async throws -> CoinMeta {
        guard let denom = normalizeDenom(from: input),
              let symbol = symbol(from: input) else {
            throw ResolverError.invalidFormat
        }

        var decimals = 8
        do {
            let metadata = try await service.getCosmosTokenMetadata(denom: denom)
            decimals = metadata.decimals
        } catch {
            let info = THORChainTokenMetadataFactory.create(asset: denom)
            decimals = info.decimals
        }

        let curated = TokensStore.findTokenMeta(chain: .thorChain, contractAddress: denom)
            ?? TokensStore.TokenSelectionAssets.first {
                $0.chain == .thorChain && $0.ticker.uppercased() == symbol
            }

        return CoinMeta(
            chain: .thorChain,
            ticker: curated?.ticker ?? symbol,
            logo: curated?.logo ?? symbol.lowercased(),
            decimals: decimals,
            priceProviderId: curated?.priceProviderId ?? "",
            contractAddress: denom,
            isNativeToken: false
        )
    }
}
