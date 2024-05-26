//
//  SwapCryptoTransaction.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 08.04.2024.
//

import Foundation
import BigInt

@MainActor
class SwapTransaction: ObservableObject {

    @Published var fromCoin: Coin = .example
    @Published var toCoin: Coin = .example
    @Published var fromAmount: String = .empty
    @Published var gas: BigInt = .zero
    @Published var quote: SwapQuote?

    var fromBalance: String {
        return fromCoin.balanceString
    }

    var toBalance: String {
        return toCoin.balanceString
    }

    var toAmountDecimal: Decimal {
        guard let quote else {
            return .zero
        }
        switch quote {
        case .thorchain(let quote):
            let expected = Decimal(string: quote.expectedAmountOut) ?? 0
            return expected / Decimal(100_000_000)
        case .oneinch(let quote):
            let amount = BigInt(quote.dstAmount) ?? BigInt.zero
            return toCoin.decimal(for: amount)
        }
    }

    var toAmountRaw: BigInt {
        guard let quote else {
            return .zero
        }
        switch quote {
        case .thorchain:
            return toCoin.raw(for: toAmountDecimal)
        case .oneinch(let quote):
            return BigInt(quote.dstAmount) ?? BigInt.zero
        }
    }

    var router: String? {
        return quote?.router
    }

    var inboundFeeDecimal: Decimal? {
        return quote?.inboundFeeDecimal(toCoin: toCoin)
    }
    
    var gasInReadable: String {
        guard var decimals = Int(toCoin.decimals) else {
            return .empty
        }
        if toCoin.chain.chainType == .EVM {
            // convert to Gwei , show as Gwei for EVM chain only
            guard let weiPerGWeiDecimal = Decimal(string: EVMHelper.weiPerGWei.description) else {
                return .empty
            }
            return "\(Decimal(gas) / weiPerGWeiDecimal) \(toCoin.feeUnit)"
        }
        
        // If not a native token we need to get the decimals from the native token
        if !toCoin.isNativeToken {
            if let vault = ApplicationState.shared.currentVault {
                if let nativeToken = vault.coins.first(where: { $0.isNativeToken && $0.chain.name == toCoin.chain.name }) {
                    decimals = Int(nativeToken.decimals) ?? .zero
                }
            }
        }
        
        return "\((Decimal(gas) / pow(10,decimals)).formatToDecimal(digits: decimals).description) \(toCoin.feeUnit)"
    }
}

extension SwapTransaction {
    
    var amountDecimal: Decimal {
        let amountString = fromAmount.replacingOccurrences(of: ",", with: ".")
        return Decimal(string: amountString) ?? .zero
    }
    
    var amountInCoinDecimal: BigInt {
        return fromCoin.raw(for: amountDecimal)
    }
}
