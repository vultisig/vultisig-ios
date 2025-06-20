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
        case .kyberSwap:
            return "KyberSwap"
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

        let amountDecimal = fromCoin.decimal(for: amount)
        let formattedAmount = amountDecimal >= 1_000_000 ? 
            amountDecimal.formatWithAbbreviation() : 
            amountDecimal.formatDecimalToLocale()
        return "\(formattedAmount) \(fromCoin.ticker)"
    }

    func getFromAmount(_ keysignPayload: KeysignPayload?) -> String {
        guard let payload = keysignPayload?.swapPayload else { return .empty }
        let amount = payload.fromCoin.decimal(for: payload.fromAmount)
        let formattedAmount = amount >= 1_000_000 ? 
            amount.formatWithAbbreviation() : 
            amount.formatDecimalToLocale()
        
        if payload.fromCoin.chain == payload.toCoin.chain {
            return "\(formattedAmount) \(payload.fromCoin.ticker)"
        } else {
            return "\(formattedAmount) \(payload.fromCoin.ticker) (\(payload.fromCoin.chain.ticker))"
        }
    }

    func getToAmount(_ keysignPayload: KeysignPayload?) -> String {
        guard let payload = keysignPayload?.swapPayload else { return .empty }
        let amount = payload.toAmountDecimal
        let formattedAmount = amount >= 1_000_000 ? 
            amount.formatWithAbbreviation() : 
            amount.formatDecimalToLocale()
        
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
    
    func getFromAmountString(_ keysignPayload: KeysignPayload?) -> String {
        guard let payload = keysignPayload?.swapPayload else { return "" }
        let amount = payload.fromCoin.decimal(for: payload.fromAmount)
        return amount >= 1_000_000 ? 
            amount.formatWithAbbreviation() : 
            amount.formatDecimalToLocale()
    }
    
    func getToCoin(_ keysignPayload: KeysignPayload?) -> Coin? {
        guard let payload = keysignPayload?.swapPayload else { return nil }
        return payload.toCoin
    }
    
    func getToAmountString(_ keysignPayload: KeysignPayload?) -> String {
        guard let payload = keysignPayload?.swapPayload else { return .empty }
        let amount = payload.toAmountDecimal
        return amount >= 1_000_000 ? 
            amount.formatWithAbbreviation() : 
            amount.formatDecimalToLocale()
    }
}
