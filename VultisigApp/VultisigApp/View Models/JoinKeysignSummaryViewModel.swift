//
//  JoinKeysignSummaryViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-12-05.
//

import Foundation

class JoinKeysignSummaryViewModel {
    func getAction(_ keysignPayload: KeysignPayload?) -> String {
        guard keysignPayload?.approvePayload == nil else {
            return NSLocalizedString("approveAndSwap", comment: "")
        }
        return NSLocalizedString("swap", comment: "")
    }

    func getProvider(_ keysignPayload: KeysignPayload?) -> String {
        switch keysignPayload?.swapPayload {
        case .oneInch:
            return "1Inch"
        case .thorchain:
            return "THORChain"
        case .mayachain:
            return "Maya protocol"
        case .none:
            return .empty
        }
    }

    func getSpender(_ keysignPayload: KeysignPayload?) -> String {
        return keysignPayload?.approvePayload?.spender ?? .empty
    }

    func getAmount(_ keysignPayload: KeysignPayload?, selectedCurrency: SettingsCurrency) -> String {
        guard let fromCoin = keysignPayload?.coin, let amount = keysignPayload?.approvePayload?.amount else {
            return .empty
        }

        return "\(String(describing: fromCoin.decimal(for: amount)).formatCurrencyWithSeparators()) \(fromCoin.ticker)"
    }

    func getFromAmount(_ keysignPayload: KeysignPayload?, selectedCurrency: SettingsCurrency) -> String {
        guard let payload = keysignPayload?.swapPayload else { return .empty }
        let amount = payload.fromCoin.decimal(for: payload.fromAmount)
        if payload.fromCoin.chain == payload.toCoin.chain {
            return "\(String(describing: amount).formatCurrencyWithSeparators()) \(payload.fromCoin.ticker)"
        } else {
            return "\(String(describing: amount).formatCurrencyWithSeparators()) \(payload.fromCoin.ticker) (\(payload.fromCoin.chain.ticker))"
        }
    }

    func getToAmount(_ keysignPayload: KeysignPayload?, selectedCurrency: SettingsCurrency) -> String {
        guard let payload = keysignPayload?.swapPayload else { return .empty }
        let amount = payload.toAmountDecimal
        if payload.fromCoin.chain == payload.toCoin.chain {
            return "\(String(describing: amount).formatCurrencyWithSeparators()) \(payload.toCoin.ticker)"
        } else {
            return "\(String(describing: amount).formatCurrencyWithSeparators()) \(payload.toCoin.ticker) (\(payload.toCoin.chain.ticker))"
        }
    }
}
