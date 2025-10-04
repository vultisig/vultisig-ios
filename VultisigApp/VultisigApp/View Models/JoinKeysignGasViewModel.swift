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
    func getCalculatedNetworkFee(payload: KeysignPayload, vault: Vault? = nil) -> (feeCrypto: String, feeFiat: String) {
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

            var feeInReadable = feesInReadable(coin: payload.coin, fee: payload.chainSpecific.fee, vault: vault)
            feeInReadable = feeInReadable.nilIfEmpty.map { $0 } ?? ""

            return ("\(gasInReadable) \(payload.coin.chain.feeUnit)", feeInReadable)
        }

        let gasAmount = Decimal(payload.chainSpecific.gas) / pow(10, nativeToken.decimals)
        let gasInReadable = gasAmount.formatToDecimal(digits: nativeToken.decimals)

        var feeInReadable = feesInReadable(coin: payload.coin, fee: payload.chainSpecific.gas, vault: vault)
        feeInReadable = feeInReadable.nilIfEmpty.map { $0 } ?? ""

        return ("\(gasInReadable) \(payload.coin.chain.feeUnit)", feeInReadable)
    }
    
    func getJoinedCalculatedNetworkFee(payload: KeysignPayload, vault: Vault? = nil) -> String {
        let fees = getCalculatedNetworkFee(payload: payload, vault: vault)
        return fees.feeCrypto + " (~\(fees.feeFiat))"
    }
    
    func feesInReadable(coin: Coin, fee: BigInt, vault: Vault? = nil) -> String {
        // Use provided vault or fallback to ApplicationState
        let targetVault = vault ?? ApplicationState.shared.currentVault
        guard let targetVault = targetVault else {
            return ""
        }
        
        guard let nativeCoin = targetVault.nativeCoin(for: coin.chain) else {
            return ""
        }
        
        let feeDecimal = nativeCoin.decimal(for: fee)
        let fiatString = RateProvider.shared.fiatBalanceString(value: feeDecimal, coin: nativeCoin)
        
        // If fiat string is empty, try with the original payload coin as fallback
        if fiatString.isEmpty {
            let fallbackFiatString = RateProvider.shared.fiatBalanceString(value: feeDecimal, coin: coin)
            return fallbackFiatString
        }
        
        return fiatString
    }
}
