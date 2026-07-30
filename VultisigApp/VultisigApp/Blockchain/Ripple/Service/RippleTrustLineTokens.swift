//
//  RippleTrustLineTokens.swift
//  VultisigApp
//

import Foundation

private let logger = Log.chain.service

/// Maps XRPL trust lines onto the token coins worth surfacing in the asset list.
/// Kept pure and separate from `RippleService` so the filtering rules can be
/// pinned without a network round-trip.
enum RippleTrustLineTokens {

    /// The issued currencies to auto-add for an account.
    ///
    /// Only **strictly positive** balances are surfaced. A negative balance means
    /// the account is the token's issuer and owes the counterparty — an issuance
    /// liability rather than a holding — and a zero balance is an open-but-empty
    /// trust line that would only clutter the asset list.
    ///
    /// A curated `TokensStore` entry wins when one exists: it carries the bundled
    /// logo and a working `priceProviderId`, neither of which the ledger can
    /// supply. XRPL has no on-ledger token metadata registry, so everything else
    /// is derived from the currency code itself.
    static func discoverableTokens(from lines: [RippleTrustLine]) -> [CoinMeta] {
        lines.compactMap { line -> CoinMeta? in
            do {
                let balance = try RippleIssuedCurrency.parseIssuedCurrencyValue(line.balance)
                guard balance > 0 else { return nil }

                let tokenId = try RippleIssuedCurrency.rippleTokenId(
                    currency: line.currency,
                    issuer: line.account
                )

                if let curated = TokensStore.findTokenMeta(chain: .ripple, contractAddress: tokenId) {
                    return curated
                }

                return CoinMeta(
                    chain: .ripple,
                    ticker: RippleIssuedCurrency.toIssuedCurrencyTicker(line.currency),
                    logo: .empty,
                    decimals: RippleIssuedCurrency.issuedCurrencyDecimals,
                    priceProviderId: .empty,
                    contractAddress: tokenId,
                    isNativeToken: false
                )
            } catch {
                // An unreadable currency code or value is not evidence of a
                // holding, so the line is skipped rather than surfaced with a
                // guessed balance.
                logger.warning(
                    "Skipping XRPL trust line \(line.currency, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                return nil
            }
        }
    }
}
