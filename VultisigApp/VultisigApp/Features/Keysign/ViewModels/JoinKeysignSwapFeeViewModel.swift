//
//  JoinKeysignSwapFeeViewModel.swift
//  VultisigApp
//

import Foundation
import BigInt

/// Resolves the swap-fee row shown on the co-signer's swap confirm screen.
/// The co-signer holds only the serialized keysign payload (no live quote),
/// so the fee coin is reconstructed from the payload's coin context. The
/// resolver never guesses: whenever the fee cannot be attributed to a coin
/// with certainty it returns nil and the UI renders no row — a missing row
/// beats a fiat value that's wrong by orders of magnitude.
struct JoinKeysignSwapFeeViewModel {

    struct ResolvedSwapFee {
        /// Fee in human units. Scaled by the wire decimals (not the resolved
        /// coin's) — the sender serialized the raw amount in those units.
        let amount: Decimal
        /// Display coin: supplies ticker and rate identity.
        let coin: CoinMeta
    }

    /// Formatted (crypto, fiat) strings for the swap-fee row, or nil for no
    /// row. Fiat is empty when no rate is available, consistent with the
    /// network-fee row.
    func getSwapFee(swapPayload: SwapPayload?, vault: Vault?) -> (feeCrypto: String, feeFiat: String)? {
        guard let resolved = resolveSwapFee(swapPayload: swapPayload, vault: vault) else {
            return nil
        }
        let cryptoString = "\(resolved.amount.formatForDisplay()) \(resolved.coin.ticker)"
        let fiatString: String
        if let rate = RateProvider.shared.rate(for: resolved.coin) {
            let fiatValue = RateProvider.shared.fiatBalance(value: resolved.amount, rate: rate)
            fiatString = fiatValue.formatToFiatForFee(includeCurrencySymbol: true)
        } else {
            fiatString = .empty
        }
        return (cryptoString, fiatString)
    }

    func resolveSwapFee(swapPayload: SwapPayload?, vault: Vault?) -> ResolvedSwapFee? {
        switch swapPayload {
        case let .thorchain(payload), let .thorchainChainnet(payload),
             let .thorchainStagenet(payload), let .mayachain(payload):
            return resolveNativeSwapFee(payload: payload)
        case let .generic(payload):
            return resolveGenericSwapFee(payload: payload, vault: vault)
        case .swapkit, .none:
            // SwapKit keeps its fee in a wire group this payload shape lacks.
            return nil
        }
    }

    /// Native routes charge in the destination asset, so `toCoin` is the fee coin.
    /// Not `SwapCryptoLogic.swapFeeCoin`: native quotes carry no
    /// `swapFeeTokenContract`, so it would fall through to the source gas coin.
    private func resolveNativeSwapFee(payload: THORChainSwapPayload) -> ResolvedSwapFee? {
        // `>= 0`, not `> 0`: a stated zero renders a `$0.00` row to match the
        // initiator. Only an absent fee hides the row.
        guard let rawFee = payload.fee?.nilIfEmpty,
              let amount = Decimal(string: rawFee),
              amount >= 0 else { return nil }
        let multiplier = payload.toCoin.thorswapMultiplier
        guard multiplier > 0 else { return nil }
        return ResolvedSwapFee(amount: amount / multiplier, coin: payload.toCoin.toCoinMeta())
    }

    private func resolveGenericSwapFee(payload: GenericSwapPayload, vault: Vault?) -> ResolvedSwapFee? {
        guard let fee = BigInt(payload.quote.tx.swapFee), fee > 0 else { return nil }

        // Pre-context senders omit chain/decimals — render no row rather
        // than guessing a coin (a 6-decimal destination-token fee read as an
        // 18-decimal native amount is wrong by ~10^12).
        guard
            let chainName = payload.swapFeeChain,
            let chain = Chain(name: chainName),
            let wireDecimals = payload.swapFeeDecimals
        else { return nil }

        guard let coin = resolveDisplayCoin(
            chain: chain,
            tokenId: payload.swapFeeTokenId,
            fromCoin: payload.fromCoin,
            toCoin: payload.toCoin,
            vault: vault
        ) else { return nil }

        let rawAmount = Decimal(string: String(fee)) ?? .zero
        let amount = rawAmount / pow(10, wireDecimals)
        return ResolvedSwapFee(amount: amount, coin: coin)
    }

    /// Token fees must match one side of the swap (those coins travelled
    /// with the payload, complete with price-provider identity). Native fees
    /// resolve via the vault's own coin for that chain — live rate — with a
    /// TokensStore fallback when the vault doesn't hold it. An unknown token
    /// id resolves to nothing: never guess.
    private func resolveDisplayCoin(
        chain: Chain,
        tokenId: String?,
        fromCoin: Coin,
        toCoin: Coin,
        vault: Vault?
    ) -> CoinMeta? {
        guard let tokenId = tokenId?.nilIfEmpty else {
            if let vaultNative = vault?.nativeCoin(for: chain) {
                return vaultNative.toCoinMeta()
            }
            return TokensStore.TokenSelectionAssets.first(where: {
                $0.isNativeToken && $0.chain == chain
            })
        }
        return [fromCoin, toCoin].first(where: {
            $0.chain == chain && $0.contractAddress.caseInsensitiveCompare(tokenId) == .orderedSame
        })?.toCoinMeta()
    }
}
