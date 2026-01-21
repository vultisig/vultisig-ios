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
    func getCalculatedNetworkFee(payload: KeysignPayload) -> (feeCrypto: String, feeFiat: String) {
        guard let nativeToken = TokensStore.TokenSelectionAssets.first(where: {
            $0.isNativeToken && $0.chain == payload.coin.chain
        }) else {
            return (.empty, .empty)
        }

        if payload.coin.chainType == .EVM {
            let gas = payload.chainSpecific.gas

            guard let weiPerGWeiDecimal = Decimal(string: EVMHelper.weiPerGWei.description),
                  let gasDecimal = Decimal(string: gas.description) else {
                return (.empty, .empty)
            }

            let gasGwei = gasDecimal / weiPerGWeiDecimal
            let gasInReadable = gasGwei.formatToDecimal(digits: nativeToken.decimals)

            var feeInReadable = feesInReadable(coin: payload.coin, fee: payload.chainSpecific.fee)
            feeInReadable = feeInReadable.nilIfEmpty.map { $0 } ?? ""

            return ("\(gasInReadable) \(payload.coin.chain.feeUnit)", feeInReadable)
        }

        // For UTXO and Cardano chains, calculate total fee using WalletCore (like first device)
        var feeToUse = payload.chainSpecific.gas
        if payload.coin.chainType == .UTXO {
            feeToUse = calculateUTXOTotalFee(payload: payload) ?? payload.chainSpecific.gas
        } else if payload.coin.chainType == .Cardano {
            feeToUse = calculateCardanoTotalFee(payload: payload) ?? payload.chainSpecific.gas
        }

        // Use the same fee for both crypto and fiat display for UTXO and Cardano chains
        let gasAmountToDisplay = (payload.coin.chainType == .UTXO || payload.coin.chainType == .Cardano) ? feeToUse : payload.chainSpecific.gas
        let gasAmount = Decimal(gasAmountToDisplay) / pow(10, nativeToken.decimals)
        let gasInReadable = gasAmount.formatToDecimal(digits: nativeToken.decimals)

        var feeInReadable = feesInReadable(coin: payload.coin, fee: feeToUse)
        feeInReadable = feeInReadable.nilIfEmpty.map { $0 } ?? ""

        return ("\(gasInReadable) \(nativeToken.ticker)", feeInReadable)
    }

    func getJoinedCalculatedNetworkFee(payload: KeysignPayload) -> String {
        let fees = getCalculatedNetworkFee(payload: payload)
        return fees.feeCrypto + " (~\(fees.feeFiat))"
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

        // Fallback to the payload coin itself
        let feeDecimal = coin.decimal(for: fee)
        // Use fee-specific formatting with more decimal places (5 instead of 2)
        return RateProvider.shared.fiatFeeString(value: feeDecimal, coin: coin)
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
        let helper = CardanoHelper()
        do {
            let planFee = try helper.calculateDynamicFee(keysignPayload: payload)
            return planFee > 0 ? planFee : nil
        } catch {
            return nil
        }
    }
}
