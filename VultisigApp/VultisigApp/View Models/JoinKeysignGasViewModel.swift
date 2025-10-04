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

        let gasAmount = Decimal(payload.chainSpecific.gas) / pow(10, nativeToken.decimals)
        let gasInReadable = gasAmount.formatToDecimal(digits: nativeToken.decimals)

        var feeInReadable = feesInReadable(coin: payload.coin, fee: payload.chainSpecific.gas)
        feeInReadable = feeInReadable.nilIfEmpty.map { $0 } ?? ""

        return ("\(gasInReadable) \(payload.coin.chain.feeUnit)", feeInReadable)
    }
    
    func getJoinedCalculatedNetworkFee(payload: KeysignPayload) -> String {
        let fees = getCalculatedNetworkFee(payload: payload)
        return fees.feeCrypto + " (~\(fees.feeFiat))"
    }
    
    func feesInReadable(coin: Coin, fee: BigInt) -> String {
        // Try to get native coin from vault first (has up-to-date price data)
        if let vaultNativeCoin = ApplicationState.shared.currentVault?.nativeCoin(for: coin.chain) {
            let feeDecimal = vaultNativeCoin.decimal(for: fee)
            let fiatString = RateProvider.shared.fiatBalanceString(value: feeDecimal, coin: vaultNativeCoin)
            if !fiatString.isEmpty {
                return fiatString
            }
        }
        
        // Fallback to the payload coin itself
        let feeDecimal = coin.decimal(for: fee)
        return RateProvider.shared.fiatBalanceString(value: feeDecimal, coin: coin)
    }
}
