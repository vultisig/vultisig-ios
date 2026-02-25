//
//  SwapCryptoTransaction.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 08.04.2024.
//

import Foundation
import BigInt

class SwapTransaction: ObservableObject {

    @Published var fromAmount: String = .empty
    @Published var thorchainFee: BigInt = .zero
    @Published var gas: BigInt = .zero
    @Published var vultDiscountBps: Int = 0
    @Published var referralDiscountBps: Int = 0
    @Published var quote: SwapQuote?
    @Published var isFastVault: Bool = false
    @Published var fastVaultPassword: String = .empty

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

    var isDeposit: Bool {
        // isDeposit should be true for Maya chain swaps
        if fromCoin.chain == .mayaChain {
            return true
        }

        return false
    }

    var fee: BigInt {
        switch quote {
        case .thorchain, .thorchainChainnet, .thorchainStagenet, .mayachain:
            return thorchainFee
        case .oneinch(_, let fee), .kyberswap(_, let fee), .lifi(_, let fee, _):
            return fee ?? 0
        case nil:
            return .zero
        }
    }

    var toAmountDecimal: Decimal {
        guard let quote else {
            return .zero
        }
        switch quote {
        case .mayachain(let quote), .thorchain(let quote), .thorchainChainnet(let quote), .thorchainStagenet(let quote):
            let expected = quote.expectedAmountOut.toDecimal()
            return expected / toCoin.thorswapMultiplier
        case .oneinch(let quote, _), .lifi(let quote, _, _):
            let amount = BigInt(quote.dstAmount) ?? BigInt.zero
            return toCoin.decimal(for: amount)
        case .kyberswap(let quote, _):
            let amount = BigInt(quote.dstAmount) ?? BigInt.zero
            return toCoin.decimal(for: amount)
        }
    }

    var router: String? {
        return quote?.router
    }

    var inboundFeeDecimal: Decimal? {
        return quote?.inboundFeeDecimal(toCoin: toCoin)
    }

    var isAffiliate: Bool {
        let fiatAmount = RateProvider.shared.fiatBalance(
            value: fromAmountDecimal,
            coin: fromCoin.toCoinMeta(),
            currency: .USD
        )

        return fiatAmount >= 100
    }
}

extension SwapTransaction {

    var fromAmountDecimal: Decimal {
        return fromAmount.toDecimal()
    }

    var amountInCoinDecimal: BigInt {
        return fromCoin.raw(for: fromAmount.toDecimal())
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
            isAffiliate: isAffiliate
        )
        return swapPayload
    }
}
