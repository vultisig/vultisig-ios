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
        var nativeCoinAux: Coin?
        
        if coin.isNativeToken {
            nativeCoinAux = coin
        } else {
            nativeCoinAux = ApplicationState.shared.currentVault?.coins.first(where: { $0.chain == coin.chain && $0.isNativeToken })
        }
        
        guard let nativeCoin = nativeCoinAux else {
            return ""
        }
        
        let fee = nativeCoin.decimal(for: fee)
        return RateProvider.shared.fiatBalanceString(value: fee, cryptoId:  nativeCoin.cryptoId())
    }
}
