//
//  JoinKeysignGasViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/07/2025.
//

import Foundation
import BigInt

// TODO: - Extend and reuse for both on-device and co-pairing signing
struct JoinKeysignGasViewModel {

    private struct ResolvedNetworkFee {
        let amount: BigInt
        let nativeToken: CoinMeta
    }

    func getCalculatedNetworkFee(payload: KeysignPayload) -> (feeCrypto: String, feeFiat: String) {
        guard let resolved = resolveNetworkFee(payload: payload) else {
            return (.empty, .empty)
        }
        let gasAmount = Decimal(resolved.amount) / pow(10, resolved.nativeToken.decimals)
        let gasInReadable = gasAmount.formatToDecimal(digits: resolved.nativeToken.decimals)
        let feeInReadable = feesInReadable(coin: payload.coin, fee: resolved.amount)
        return ("\(gasInReadable) \(resolved.nativeToken.ticker)", feeInReadable)
    }

    /// `nil` when nothing prices the fee coin, so a caller summing this never
    /// absorbs an unpriced leg as free.
    func networkFeeFiat(payload: KeysignPayload, vault: Vault? = nil) -> Decimal? {
        guard let resolved = resolveNetworkFee(payload: payload) else { return nil }
        // Gas is always paid in the native coin. A priced source token cannot
        // stand in for an unavailable native rate, even on the same chain.
        let feeCoin = vault?.nativeCoin(for: payload.coin.chain)?.toCoinMeta()
            ?? (payload.coin.isNativeToken ? payload.coin.toCoinMeta() : resolved.nativeToken)
        guard let rate = RateProvider.shared.rate(for: feeCoin) else { return nil }
        let amount = Decimal(resolved.amount) / pow(10, resolved.nativeToken.decimals)
        return RateProvider.shared.fiatBalance(value: amount, rate: rate)
    }

    private func resolveNetworkFee(payload: KeysignPayload) -> ResolvedNetworkFee? {
        guard let nativeToken = TokensStore.TokenSelectionAssets.first(where: {
            $0.isNativeToken && $0.chain == payload.coin.chain
        }) else {
            return nil
        }

        // When the dApp supplied explicit fee data via signAmino (e.g. Rujira
        // CosmWasm calls where fee.amount = 0), prefer that over the estimated
        // blockchainSpecific fee. This prevents the UI from showing a misleading
        // non-zero network fee when the chain actually charges nothing.
        // Parity with vultisig-windows PR #3843.
        if let dappFee = payload.dappSuppliedCosmosFee() {
            return ResolvedNetworkFee(amount: BigInt(dappFee), nativeToken: nativeToken)
        }

        if payload.coin.chainType == .EVM {
            // `chainSpecific.fee` values the EVM fee at the oracle inputs alone,
            // but swaps riding the `.generic` payload are signed with the shared
            // `EVMSwapFee` reconciliation — the quote's own gas price bumped to
            // the oracle ceiling, the route gas floored by the oracle limit
            // (with the zero-gas fallback). Value the fee exactly the way the
            // vault signs it so the co-signer matches the initiator's display.
            // THORChain/Maya swap payloads keep `chainSpecific.fee` — their
            // signer prices purely from chainSpecific, already consistent.
            var totalFeeWei = payload.chainSpecific.fee
            if case .Ethereum(let maxFeePerGasWei, _, _, let gasLimit) = payload.chainSpecific,
               case .generic(let generic)? = payload.swapPayload {
                totalFeeWei = EVMSwapFee.effective(
                    quoteGasPriceWei: EVMSwapFee.quoteGasPriceWei(generic.quote.tx.gasPrice),
                    quoteGas: BigInt(generic.quote.tx.gas),
                    maxFeePerGasWei: maxFeePerGasWei,
                    gasLimit: gasLimit
                ).feeWei
            }
            return ResolvedNetworkFee(amount: totalFeeWei, nativeToken: nativeToken)
        }

        // A Solana payload carrying an injected ComputeBudget pair costs
        // `limit × price` on top of the flat estimate, and `chainSpecific.gas`
        // does not account for it. The initiator's verify screen adds it via
        // `PrebuiltPayloadFee`; without this the two devices would quote
        // different fees for the same bytes, which is the one thing a co-signer
        // has no way to reconcile.
        if payload.coin.chainType == .Solana,
           case .Solana(_, let priorityFee, let priorityLimit, _, _, _) = payload.chainSpecific,
           priorityFee > 0, priorityLimit > 0,
           let total = PrebuiltPayloadFee.fee(for: payload) {
            return ResolvedNetworkFee(amount: total, nativeToken: nativeToken)
        }

        // For UTXO and Cardano chains, calculate total fee using WalletCore (like first device)
        var feeToUse = payload.chainSpecific.gas
        if payload.coin.chainType == .UTXO {
            feeToUse = calculateUTXOTotalFee(payload: payload) ?? payload.chainSpecific.gas
        } else if payload.coin.chainType == .Cardano {
            feeToUse = calculateCardanoTotalFee(payload: payload) ?? payload.chainSpecific.gas
        }

        return ResolvedNetworkFee(amount: feeToUse, nativeToken: nativeToken)
    }

    func feesInReadable(coin: Coin, fee: BigInt) -> String {
        // Try to get native coin from vault first (has up-to-date price data)
        if let vaultNativeCoin = AppViewModel.shared.selectedVault?.nativeCoin(for: coin.chain) {
            let feeDecimal = vaultNativeCoin.decimal(for: fee)
            // Use fee-specific formatting with more decimal places (5 instead of 2)
            let fiatString = RateProvider.shared.fiatFeeString(value: feeDecimal, coin: vaultNativeCoin)
            if !fiatString.isEmpty {
                return fiatString
            }
        }

        // Fallback: the fee is always denominated in the chain's native coin, never
        // the payload's token coin (e.g. an ERC-20) — pricing with `coin` here priced
        // a native-coin amount at the token's rate.
        guard let nativeToken = TokensStore.TokenSelectionAssets.first(where: {
            $0.isNativeToken && $0.chain == coin.chain
        }) else {
            return .empty
        }
        let feeDecimal = Decimal(fee) / pow(10, nativeToken.decimals)
        return RateProvider.shared.fiatFeeString(value: feeDecimal, coin: nativeToken)
    }

    private func calculateUTXOTotalFee(payload: KeysignPayload) -> BigInt? {
        guard let helper = UTXOChainsHelper.getHelper(coin: payload.coin) else {
            return nil
        }

        do {
            let plan = try helper.getBitcoinTransactionPlan(keysignPayload: payload)
            return plan.fee > 0 ? BigInt(plan.fee) : nil
        } catch {
            return nil
        }
    }

    private func calculateCardanoTotalFee(payload: KeysignPayload) -> BigInt? {
        do {
            let planFee = try CardanoHelper.calculateDynamicFee(keysignPayload: payload)
            return planFee > 0 ? planFee : nil
        } catch {
            return nil
        }
    }
}
