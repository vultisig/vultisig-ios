//
//  RippleCustomTokenResolver.swift
//  VultisigApp
//

import Foundation

/// Resolves a user-typed XRPL issued-currency identifier into a ``CoinMeta`` for
/// the custom-token flow.
///
/// XRPL keys a token by the **(currency, issuer) pair**, not by a single contract
/// address, so the identifier is the composite `<currency>.<issuer>` token id
/// (`USD.rHb9…`) that ``RippleIssuedCurrency/rippleTokenId(currency:issuer:)``
/// produces. The shared `AddressService.validateAddress` would reject that shape
/// outright — it is reserved for real send/receive addresses — so validation is
/// split: the issuer half goes through `AddressService`, the currency half is
/// checked against XRPL's on-ledger currency-code shapes.
///
/// **There is nothing to fetch.** Unlike an ERC-20's `name()` / `symbol()` /
/// `decimals()`, XRPL has no on-ledger token metadata registry, so a
/// well-formed pair cannot be confirmed to be a real, reputable token — only to
/// be well-formed. Everything this resolver returns is derived from the
/// identifier itself (or from a curated ``TokensStore`` entry), and the UI must
/// not imply validation it cannot perform.
///
/// Kept as a standalone, network-free type so it drops straight into the
/// `CustomTokenResolver` protocol + factory once the custom-token view-model
/// refactor lands, rather than living inline in the view.
enum RippleCustomTokenResolver {

    enum ResolverError: Error, LocalizedError {
        case invalidFormat

        var errorDescription: String? {
            switch self {
            case .invalidFormat:
                return "rippleCustomTokenInvalidFormat".localized
            }
        }
    }

    /// XRPL standard currency codes are exactly 3 characters; anything else must
    /// already be written as the 160-bit (40-hex-character) form.
    private static let standardCurrencyCodeLength = 3
    private static let hexCurrencyCodeLength = 40

    /// A trust line cannot exist without a funded XRP account to own it (it costs
    /// an owner reserve), so the custom-token flow must refuse to add an XRPL
    /// token to a vault that hasn't enabled XRP.
    static let requiresVaultNativeCoin = true

    /// Whether `input` is a well-formed XRPL token id, without touching the
    /// network. Ports the SDK's `isValidTokenId` Ripple arm:
    ///
    /// 1. it splits into a non-empty currency and issuer on the first `.`;
    /// 2. the currency is a valid ON-LEDGER code — a 3-character standard code
    ///    (`USD`) or the 40-character hex form. A bare `RLUSD` is deliberately
    ///    NOT valid: 5 characters is neither, and accepting it would let two
    ///    spellings of the same token become two different coins. It is valid
    ///    only once normalized to hex (which is how the curated catalog entry
    ///    and the token picker spell it);
    /// 3. the issuer is a real XRPL address.
    static func isValidInput(_ input: String) -> Bool {
        normalized(from: input) != nil
    }

    /// The `(currency, issuer)` pair for a valid input, with the currency
    /// normalized to its on-ledger code, or `nil` when the input is malformed.
    static func normalized(from input: String) -> (currency: String, issuer: String)? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token = try? RippleIssuedCurrency.parseRippleTokenId(trimmed) else {
            return nil
        }
        guard isValidOnLedgerCurrencyCode(token.currency) else { return nil }
        guard AddressService.validateAddress(address: token.issuer, chain: .ripple) else {
            return nil
        }
        guard let code = try? RippleIssuedCurrency.toXrplCurrencyCode(token.currency) else {
            return nil
        }
        return (code, token.issuer)
    }

    /// A currency code the ledger itself can carry: a 3-character standard code,
    /// or the 40-character hex form (case-insensitive, normalized to uppercase
    /// downstream).
    private static func isValidOnLedgerCurrencyCode(_ currency: String) -> Bool {
        if currency.utf16.count == standardCurrencyCodeLength {
            // The standard form excludes `XRP` itself — that spelling is
            // reserved for the native asset and can never be an issued currency.
            return currency.uppercased() != "XRP"
        }
        guard currency.utf16.count == hexCurrencyCodeLength else { return false }
        return currency.allSatisfy { $0.isHexDigit && $0.isASCII }
    }

    /// Resolves a validated token id into a ``CoinMeta``.
    ///
    /// No network call: `decimals` is always
    /// ``RippleIssuedCurrency/issuedCurrencyDecimals`` (15) because XRPL carries
    /// 15 significant digits for every issued currency rather than a per-token
    /// on-chain scale, and the ticker is decoded back out of the currency code
    /// (`524C555344…00` → `RLUSD`). A curated ``TokensStore`` entry wins when one
    /// exists: it carries the bundled logo and a working `priceProviderId`,
    /// neither of which the ledger can supply.
    static func resolve(input: String) throws -> CoinMeta {
        guard let (currency, issuer) = normalized(from: input) else {
            throw ResolverError.invalidFormat
        }

        let tokenId = "\(currency).\(issuer)"

        if let curated = TokensStore.findTokenMeta(chain: .ripple, contractAddress: tokenId) {
            return curated
        }

        return CoinMeta(
            chain: .ripple,
            ticker: RippleIssuedCurrency.toIssuedCurrencyTicker(currency),
            logo: .empty,
            decimals: RippleIssuedCurrency.issuedCurrencyDecimals,
            priceProviderId: .empty,
            contractAddress: tokenId,
            isNativeToken: false
        )
    }
}
