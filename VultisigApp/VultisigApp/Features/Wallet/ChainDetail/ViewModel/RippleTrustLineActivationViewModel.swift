//
//  RippleTrustLineActivationViewModel.swift
//  VultisigApp
//

import BigInt
import Foundation
import OSLog
import VultisigCommonData

private let logger = Logger(subsystem: "com.vultisig.app", category: "ripple-trust-line-activation")

/// Drives the trust-line activation sheet: what opening the line costs, whether
/// the vault's XRP covers it, and the `SendTransaction` that carries the TrustSet
/// into the shared verify → keysign flow.
///
/// The owner-reserve cost is read LIVE from `server_state`'s `reserve_inc`
/// through the existing live → cache → seed chain, never hardcoded: "0.2 XRP" is
/// a current mainnet validator-vote value, not a network constant.
@MainActor
final class RippleTrustLineActivationViewModel: ObservableObject {

    @Published private(set) var quote: RippleTrustLineActivationQuote?
    @Published private(set) var isLoading = false
    /// Set when the cost can't be quoted at all — the sheet shows this instead of
    /// an Activate button it can't price.
    @Published private(set) var errorMessage: String?

    private let service: RippleService

    init(service: RippleService = .shared) {
        self.service = service
    }

    /// Quotes the activation of `coin`'s trust line, paid for from `nativeCoin`.
    ///
    /// - Parameters:
    ///   - coin: the issued-currency coin whose line will be opened.
    ///   - nativeCoin: the vault's XRP coin. Its `rawBalance` is already
    ///     reserve-net, so it is the genuinely spendable figure.
    func load(coin: Coin, nativeCoin: Coin) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let (currency, issuer) = try? RippleIssuedCurrency.parseRippleTokenId(coin.contractAddress),
              let currencyCode = try? RippleIssuedCurrency.toXrplCurrencyCode(currency),
              let limitValue = RippleTrustLineLimit.defaultLimitDisplayValue() else {
            errorMessage = "rippleTrustLineInvalidTokenError".localized
            return
        }

        // Live → cache → seed. A seeded value is explicitly acceptable here: the
        // figure is a validation/display input, and refusing to quote because
        // `server_state` is briefly unreachable would block a legitimate
        // activation rather than protect anything.
        let reserveValues = (try? await service.fetchReserveValues()) ?? nil
        let ownerReserve = RippleReserve.reservedDrops(
            ownerCount: 1,
            reserveBase: 0,
            reserveInc: reserveValues?.reserveInc
        )
        let fee = await service.fetchFee()

        quote = RippleTrustLineActivationQuote(
            ownerReserveDrops: ownerReserve,
            feeDrops: fee,
            spendableDrops: nativeCoin.rawBalance.toBigInt(decimals: nativeCoin.decimals),
            limitValue: limitValue,
            currencyCode: currencyCode,
            issuer: issuer
        )
    }

    /// The transaction that opens the trust line.
    ///
    /// `amount` is the trust-line LIMIT, and `transactionType` is what tells every
    /// signing device so — without it the same payload reads as a token transfer.
    /// `toAddress` is the ISSUER: a TrustSet has no XRPL destination field at all,
    /// and the signer never reads `toAddress` on this path, but a payload has to
    /// carry something and the issuer is the account the line is actually with.
    /// The verify summary suppresses the destination row for a TrustSet and shows
    /// a labelled issuer row instead, so it is never presented as a recipient.
    func makeActivationTransaction(coin: Coin, vault: Vault) -> SendTransaction? {
        guard let quote else { return nil }
        return SendTransaction.empty(coin: coin, vault: vault)
            .copy(
                toAddress: quote.issuer,
                amount: quote.limitValue,
                transactionType: .rippleTrustSet
            )
    }

    /// Formatted strings for the sheet. Kept here rather than in the view so the
    /// view stays declarative.
    var ownerReserveXRP: String? {
        quote.map { RippleReserve.xrpAmount(drops: $0.ownerReserveDrops) }
    }

    var feeXRP: String? {
        quote.map { RippleReserve.xrpAmount(drops: $0.feeDrops) }
    }

    var spendableXRP: String? {
        quote.map { RippleReserve.xrpAmount(drops: $0.spendableDrops) }
    }

    var remainingSpendableXRP: String? {
        quote.map { RippleReserve.xrpAmount(drops: $0.remainingSpendableDrops) }
    }

    var totalCostXRP: String? {
        quote.map { RippleReserve.xrpAmount(drops: $0.totalCostDrops) }
    }

    /// Blocking copy shown when spendable XRP won't cover `reserve_inc + fee`.
    /// `nil` when the activation is affordable (or not yet quoted).
    var insufficientXRPMessage: String? {
        guard let quote, !quote.isAffordable, let totalCostXRP else { return nil }
        return String(format: "rippleTrustLineInsufficientXrpError".localized, totalCostXRP)
    }

    var canActivate: Bool {
        guard let quote else { return false }
        return quote.isAffordable
    }
}
