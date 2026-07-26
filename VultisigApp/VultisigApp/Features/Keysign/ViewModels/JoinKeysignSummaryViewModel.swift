//
//  JoinKeysignSummaryViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-12-05.
//

import Foundation

class JoinKeysignSummaryViewModel {
    let gasViewModel = JoinKeysignGasViewModel()

    func getFromAmount(_ keysignPayload: KeysignPayload?) -> String {
        guard let payload = keysignPayload?.swapPayload else { return .empty }
        let amount = payload.fromCoin.decimal(for: payload.fromAmount)
        let formattedAmount = amount.formatForDisplay()

        if payload.fromCoin.chain == payload.toCoin.chain {
            return "\(formattedAmount) \(payload.fromCoin.ticker)"
        } else {
            return "\(formattedAmount) \(payload.fromCoin.ticker) (\(payload.fromCoin.chain.ticker))"
        }
    }

    func getToAmount(_ keysignPayload: KeysignPayload?) -> String {
        guard let payload = keysignPayload?.swapPayload else { return .empty }
        let amount = payload.toAmountDecimal
        let formattedAmount = amount.formatForDisplay()

        if payload.fromCoin.chain == payload.toCoin.chain {
            return "\(formattedAmount) \(payload.toCoin.ticker)"
        } else {
            return "\(formattedAmount) \(payload.toCoin.ticker) (\(payload.toCoin.chain.ticker))"
        }
    }

    func getFromCoin(_ keysignPayload: KeysignPayload?) -> Coin? {
        guard let payload = keysignPayload?.swapPayload else { return nil }
        return payload.fromCoin
    }

    func getToCoin(_ keysignPayload: KeysignPayload?) -> Coin? {
        guard let payload = keysignPayload?.swapPayload else { return nil }
        return payload.toCoin
    }

}
