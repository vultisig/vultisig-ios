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

    @Published var fromAmount: String = .empty
    @Published var thorchainFee: BigInt = .zero
    @Published var oneInchFee: BigInt = .zero
    @Published var gas: BigInt = .zero
    @Published var quote: SwapQuote?

    @Published var fromCoin: Coin = .example
    @Published var toCoin: Coin = .example
    @Published var fromCoins: [Coin] = []
    @Published var toCoins: [Coin] = [] 

    func load(fromCoin: Coin, toCoin: Coin, fromCoins: [Coin], toCoins: [Coin]) {
        self.fromCoin = fromCoin
        self.toCoin = toCoin
        self.fromCoins = fromCoins
        self.toCoins = toCoins
    }

    var isApproveRequired: Bool {
        return fromCoin.shouldApprove && router != nil
    }

    var fee: BigInt {
        switch quote {
        case .thorchain, .mayachain:
            return thorchainFee
        case .oneinch, .lifi:
            return oneInchFee
        case nil:
            return .zero
        }
    }

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
        case .mayachain(let quote), .thorchain(let quote):
            let expected = Decimal(string: quote.expectedAmountOut) ?? 0
            return expected / toCoin.thorswapMultiplier
        case .oneinch(let quote), .lifi(let quote):
            let amount = BigInt(quote.dstAmount) ?? BigInt.zero
            return toCoin.decimal(for: amount)
        }
    }

    var toAmountRaw: BigInt {
        guard let quote else {
            return .zero
        }
        switch quote {
        case .thorchain, .mayachain:
            return toCoin.raw(for: toAmountDecimal)
        case .oneinch(let quote), .lifi(let quote):
            return BigInt(quote.dstAmount) ?? BigInt.zero
        }
    }

    var router: String? {
        return quote?.router
    }

    var inboundFeeDecimal: Decimal? {
        return quote?.inboundFeeDecimal(toCoin: toCoin)
    }

    var isAlliliate: Bool {
        let fiatAmount = RateProvider.shared.fiatBalance(
            value: fromAmountDecimal,
            coin: fromCoin,
            currency: .USD
        )

        return fiatAmount >= 100
    }
}

extension SwapTransaction {
    
    var fromAmountDecimal: Decimal {
        let amountString = fromAmount.replacingOccurrences(of: ",", with: ".")
        return Decimal(string: amountString) ?? .zero
    }

    var amountInCoinDecimal: BigInt {
        return fromCoin.raw(for: fromAmountDecimal)
    }

    func buildThorchainSwapPayload(quote: ThorchainSwapQuote, provider: SwapProvider) -> THORChainSwapPayload {
        let vaultAddress = quote.inboundAddress ?? fromCoin.address
        let expirationTime = Date().addingTimeInterval(60 * 15) // 15 mins
        let swapPayload = THORChainSwapPayload(
            fromAddress: fromCoin.address,
            fromCoin: fromCoin,
            toCoin: toCoin,
            vaultAddress: vaultAddress,
            routerAddress: quote.router,
            fromAmount: amountInCoinDecimal,
            toAmountDecimal: toAmountDecimal,
            toAmountLimit: "0",
            streamingInterval: String(provider.streamingInterval),
            streamingQuantity: "0",
            expirationTime: UInt64(expirationTime.timeIntervalSince1970),
            isAffiliate: isAlliliate
        )
        return swapPayload
    }
}
