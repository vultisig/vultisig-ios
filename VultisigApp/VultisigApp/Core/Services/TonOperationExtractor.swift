//
//  TonOperationExtractor.swift
//  VultisigApp
//

import Foundation
import WalletCore

/// Extracts a hero-renderable summary from a TonConnect `[TonMessage]` payload.
///
/// Mirrors `ContractCallExtractor` for the EVM path: scans the messages for
/// the first recognised jetton transfer (or NFT/swap intent in the future)
/// and resolves the jetton's display metadata against the active vault and
/// the built-in token registry. The surrounding ViewModel converts the
/// returned `Display` into a `HeroContent.send`.
///
/// Multi-output messages: per the Phase 1C plan, the first message that
/// surfaces a recognised jetton transfer wins. Other messages remain in the
/// existing details list — the hero is intentionally "best effort" since the
/// user still confirms each individual message in the verify flow.
enum TonOperationExtractor {

    /// Display summary derived from one decoded TON message body.
    struct Display: Equatable {
        let amountText: String   // formatted with decimals applied
        let ticker: String
        let logo: String
        let display: String      // pre-joined "1.234 TICKER" string
        /// Pre-formatted fiat value of the jetton amount (e.g. "$12.34"),
        /// resolved against the moving coin's `RateProvider` rate. `nil` when
        /// the jetton has no price, so the hero omits the fiat sub-line.
        let fiat: String?

        init(amountText: String, ticker: String, logo: String, display: String, fiat: String? = nil) {
            self.amountText = amountText
            self.ticker = ticker
            self.logo = logo
            self.display = display
            self.fiat = fiat
        }
    }

    /// Run the extractor against a list of messages. Returns the first
    /// resolvable display, or nil if no message decodes to a known intent we
    /// can match against vault metadata.
    static func extract(messages: [TonMessage], vault: Vault) -> Display? {
        for message in messages {
            guard let intent = TonMessageBodyDecoder.decode(
                payload: message.payload,
                outerDestination: message.to
            ) else { continue }

            switch intent {
            case .jettonTransfer(let transfer):
                if let display = resolveJettonDisplay(
                    senderJettonWallet: message.to,
                    rawAmount: transfer.amount,
                    vault: vault
                ) {
                    return display
                }
            case .nftTransfer, .excesses, .swap:
                // Phase 1C surfaces jetton transfers only — everything else
                // falls through to the unmodified TonConnect details list.
                continue
            }
        }
        return nil
    }

    private static func resolveJettonDisplay(
        senderJettonWallet: String,
        rawAmount: String,
        vault: Vault
    ) -> Display? {
        // Sender's jetton wallet address comes through the BOC envelope (the
        // outer message destination). It uniquely identifies which jetton
        // master the user is moving — match it against `Coin.address` for any
        // vault coin on TON (which is the jetton wallet for jetton coins).
        guard let normalizedWallet = normalize(address: senderJettonWallet) else {
            return nil
        }

        guard let vaultMatch = vault.coins.first(where: { coin in
            coin.chain == .ton
                && !coin.isNativeToken
                && normalize(address: coin.address) == normalizedWallet
        }) else {
            return nil
        }

        let formatted = formatAmount(rawAmount: rawAmount, decimals: vaultMatch.decimals)
        return Display(
            amountText: formatted,
            ticker: vaultMatch.ticker,
            logo: vaultMatch.logo,
            display: "\(formatted) \(vaultMatch.ticker)",
            fiat: resolveFiat(rawAmount: rawAmount, coin: vaultMatch)
        )
    }

    /// Best-effort fiat for the moving jetton amount via the shared
    /// `CryptoAmountFormatter.amountInFiat` (same `RateProvider` price source
    /// as the send/fee surfaces). Returns `nil` when the jetton has no rate
    /// or the amount is zero.
    private static func resolveFiat(rawAmount: String, coin: Coin) -> String? {
        let amountDecimal = (Decimal(string: rawAmount) ?? .zero) / pow(Decimal(10), coin.decimals)
        let fiat = CryptoAmountFormatter.amountInFiat(coin: coin, amount: amountDecimal)
        return fiat.isEmpty ? nil : fiat
    }

    private static func normalize(address: String) -> String? {
        guard !address.isEmpty else { return nil }
        return TONAddressConverter.toUserFriendly(
            address: address,
            bounceable: true,
            testnet: false
        )
    }

    /// Apply decimal scaling to a raw integer amount (decimal string). Mirrors
    /// the formatter in `JoinKeysignViewModel.resolveTokenDisplay` — kept here
    /// to keep the extractor self-contained and unit-testable.
    static func formatAmount(rawAmount: String, decimals: Int) -> String {
        guard !rawAmount.isEmpty,
              rawAmount.allSatisfy({ $0.isNumber }) else { return rawAmount }
        if decimals <= 0 { return rawAmount }

        let raw = rawAmount
        let length = raw.count
        if length <= decimals {
            let pad = String(repeating: "0", count: decimals - length)
            var fractional = pad + raw
            while fractional.hasSuffix("0") { fractional.removeLast() }
            return fractional.isEmpty ? "0" : "0.\(fractional)"
        }

        let splitIndex = raw.index(raw.startIndex, offsetBy: length - decimals)
        let whole = String(raw[..<splitIndex])
        var fractional = String(raw[splitIndex...])
        while fractional.hasSuffix("0") { fractional.removeLast() }
        return fractional.isEmpty ? whole : "\(whole).\(fractional)"
    }
}
