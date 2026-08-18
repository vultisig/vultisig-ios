//
//  BlockaidSimulationInfo+HeroContent.swift
//  VultisigApp
//

import Foundation

/// Maps a resolved Blockaid simulation to the hero rendered above the verify
/// summary. Shared by the initiator (`KeysignViewModel`) and the co-signer
/// (`JoinKeysignViewModel`) so the two devices render — and price — the same
/// hero and can't drift.
extension BlockaidSimulationInfo {

    /// Hero for this simulation: a single coin row for transfers and receives,
    /// from/to rows for swaps. Fiat sub-lines are resolved best-effort against
    /// `vaultCoins` (see `heroFiat(for:amount:vaultCoins:)`).
    ///
    /// A `receive` maps to its own hero shape rather than reusing `.send`: the
    /// two render the same row, and only the label separates money arriving
    /// from money leaving.
    func heroContent(title: String?, vaultCoins: [Coin]) -> HeroContent {
        switch self {
        case .transfer(let coin, _):
            return .send(title: title, coin: primaryRow(for: coin, vaultCoins: vaultCoins))
        case .receive(let coin, _):
            return .receive(title: title, coin: primaryRow(for: coin, vaultCoins: vaultCoins))
        case .swap(let from, let to, _, _):
            return .swap(
                title: title,
                from: primaryRow(for: from, vaultCoins: vaultCoins),
                to: Self.coinAmount(
                    for: to,
                    text: heroToAmountText ?? "",
                    amount: toAmountDecimal ?? .zero,
                    vaultCoins: vaultCoins
                )
            )
        }
    }

    /// The row for the amount this simulation leads with — the transferred,
    /// received, or swapped-from coin. Only the swap's destination row reads a
    /// different amount.
    private func primaryRow(
        for coin: BlockaidSimulationCoin,
        vaultCoins: [Coin]
    ) -> HeroCoinAmount {
        Self.coinAmount(
            for: coin,
            text: heroAmountText,
            amount: primaryAmountDecimal,
            vaultCoins: vaultCoins
        )
    }

    /// One coin row of the hero. Every row resolves its ticker, logo and fiat
    /// the same way, so they are built here rather than at each call site —
    /// `text` is the pre-formatted amount shown, `amount` the same value as a
    /// Decimal for pricing.
    private static func coinAmount(
        for coin: BlockaidSimulationCoin,
        text: String,
        amount: Decimal,
        vaultCoins: [Coin]
    ) -> HeroCoinAmount {
        HeroCoinAmount(
            amount: text,
            ticker: coin.ticker,
            logo: coin.logo,
            fiat: heroFiat(for: coin, amount: amount, vaultCoins: vaultCoins)
        )
    }

    /// Best-effort fiat for a hero coin row, resolved against the active
    /// vault's coins so it shares the amount/fee `RateProvider` price source.
    /// Matches the simulated coin by chain + contract address (native when
    /// the address is nil/empty, or is a chain's native-asset sentinel).
    /// Returns `nil` when the coin isn't in the vault, has no rate, or the
    /// amount is zero — the hero simply omits the fiat sub-line rather than
    /// rendering a misleading value.
    private static func heroFiat(
        for simCoin: BlockaidSimulationCoin,
        amount: Decimal,
        vaultCoins: [Coin]
    ) -> String? {
        let match = vaultCoins.first { coin in
            guard coin.chain == simCoin.chain else { return false }
            guard let address = simCoin.address?.lowercased(),
                  !address.isEmpty,
                  !isNativeSentinel(address: address, chain: simCoin.chain) else {
                return coin.isNativeToken
            }
            return coin.contractAddress.lowercased() == address
        }
        guard let match else { return nil }
        let fiat = CryptoAmountFormatter.amountInFiat(coin: match, amount: amount)
        return fiat.isEmpty ? nil : fiat
    }

    /// The Blockaid parser encodes native SOL with the wrapped-SOL mint
    /// rather than an empty address (see `BlockaidSimulationParser`), while
    /// the vault's native SOL coin carries no contract address — so the
    /// sentinel must map back to the chain's native coin when matching.
    private static func isNativeSentinel(address: String, chain: Chain) -> Bool {
        chain == .solana && address == BlockaidSimulationParser.wrappedSolMint.lowercased()
    }
}
