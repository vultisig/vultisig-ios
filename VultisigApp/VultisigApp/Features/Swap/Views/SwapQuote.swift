//
//  SwapQuote.swift
//  VoltixApp
//
//  Created by Artur Guseinov on 08.05.2024.
//

import Foundation
import BigInt

enum SwapQuote: Hashable {
    case thorchain(ThorchainSwapQuote)
    case thorchainChainnet(ThorchainSwapQuote)
    case thorchainStagenet(ThorchainSwapQuote)
    case mayachain(ThorchainSwapQuote)
    case oneinch(EVMQuote, fee: BigInt?)
    case kyberswap(EVMQuote, fee: BigInt?)
    case lifi(EVMQuote, fee: BigInt?, integratorFee: Decimal?)
    case swapkit(SwapKitSwapResponse, fee: BigInt?, subProvider: String)

    /// True for the native-protocol routes (THORChain on any network, MayaChain)
    /// that deposit into a THOR/Maya inbound vault, so a source-chain halt can
    /// strand funds. Aggregator routes (1inch/LI.FI/KyberSwap/SwapKit) never
    /// deposit into those vaults, so the halt gate must not apply to them.
    var isNativeProtocolRoute: Bool {
        switch self {
        case .thorchain, .thorchainChainnet, .thorchainStagenet, .mayachain:
            return true
        case .oneinch, .kyberswap, .lifi, .swapkit:
            return false
        }
    }

    var swapProviderId: SwapProviderId? {
        switch self {
        case .thorchain, .thorchainChainnet, .thorchainStagenet, .mayachain:
            return nil
        case .oneinch:
            return .oneInch
        case .kyberswap:
            return .kyberSwap
        case .lifi:
            return .lifi
        case .swapkit:
            return .swapkit
        }
    }

    var router: String? {
        switch self {
        case .thorchain(let quote), .thorchainChainnet(let quote), .thorchainStagenet(let quote), .mayachain(let quote):
            return quote.router
        case .oneinch(let quote, _),
                .lifi(let quote, _, _),
                .kyberswap(let quote, _):
            return quote.tx.to
        case .swapkit(let response, _, _):
            return response.targetAddress
        }
    }

    var totalSwapSeconds: Int? {
        switch self {
        case .thorchain(let quote), .thorchainChainnet(let quote), .thorchainStagenet(let quote), .mayachain(let quote):
            return quote.totalSwapSeconds
        case .oneinch, .kyberswap, .lifi, .swapkit:
            return nil
        }
    }

    var inboundAddress: String? {
        switch self {
        case .thorchain(let quote), .thorchainChainnet(let quote), .thorchainStagenet(let quote), .mayachain(let quote):
            return quote.inboundAddress
        case .oneinch(let quote, _),
                .lifi(let quote, _, _),
                .kyberswap(let quote, _):
            return quote.tx.to
        case .swapkit(let response, _, _):
            return response.inboundAddress ?? response.targetAddress
        }
    }

    var displayName: String? {
        switch self {
        case .thorchain:
            return "THORChain"
        case .thorchainChainnet:
            return "THORChain-Chainnet"
        case .thorchainStagenet:
            return "THORChain-Stagenet"
        case .mayachain:
            return "Maya protocol"
        case .oneinch:
            return "1Inch"
        case .kyberswap:
            return "KyberSwap"
        case .lifi:
            return "LI.FI"
        case .swapkit:
            // The sub-provider (e.g. Chainflip) is carried on the payload for
            // routing/explorer links; the display name stays the clean brand.
            return "SwapKit"
        }
    }

    /// Brand-logo asset name for the provider (in `Crypto/`), matching the
    /// imageset filenames. Providers without a bundled logo (KyberSwap, SwapKit)
    /// fall back to `AsyncImageView`'s monogram.
    var providerLogo: String {
        switch self {
        case .thorchain, .thorchainChainnet, .thorchainStagenet:
            return "THORChain"
        case .mayachain:
            return "Maya protocol"
        case .oneinch:
            return "1Inch"
        case .lifi:
            return "LI.FI"
        case .kyberswap:
            return "kyberswap"
        case .swapkit:
            return "swapkit"
        }
    }

    func inboundFeeDecimal(toCoin: Coin) -> Decimal? {
        switch self {
        case .thorchain(let quote), .thorchainChainnet(let quote), .thorchainStagenet(let quote), .mayachain(let quote):
            guard let fees = Decimal(string: quote.fees.total) else { return nil }
            return fees / toCoin.thorswapMultiplier
        case .lifi(let quote, _, let integratorFee):
            // Li.Fi charges integrator fee on the output amount
            let toAmountBigInt = BigInt(quote.dstAmount) ?? .zero
            let toAmountDecimal = toCoin.decimal(for: toAmountBigInt)
            return toAmountDecimal * (integratorFee ?? 0)
        case .oneinch, .kyberswap, .swapkit:
            // Fee is in native gas token, not toCoin — handled via evmSwapFeeBigInt
            return .zero
        }
    }

    var evmSwapFeeBigInt: BigInt? {
        switch self {
        case .oneinch(let quote, _), .kyberswap(let quote, _), .lifi(let quote, _, _):
            guard let fee = BigInt(quote.tx.swapFee), fee > 0 else { return nil }
            return fee
        case .swapkit:
            // SwapKit's affiliate fee is dashboard-driven, no per-tx swap-fee
            // field on the wire today. Revisit when partner dashboard wiring
            // lands.
            return nil
        default:
            return nil
        }
    }

    var swapFeeTokenContract: String? {
        switch self {
        case .oneinch(let quote, _), .kyberswap(let quote, _), .lifi(let quote, _, _):
            let contract = quote.tx.swapFeeTokenContract
            return contract.isEmpty ? nil : contract
        default:
            return nil
        }
    }

    var memo: String? {
        switch self {
        case .thorchain(let quote), .thorchainChainnet(let quote), .thorchainStagenet(let quote), .mayachain(let quote):
            return quote.memo
        case .oneinch, .kyberswap, .lifi, .swapkit:
            return nil
        }
    }

    var priceImpact: Decimal? {
        switch self {
        case .thorchain(let quote), .thorchainChainnet(let quote), .thorchainStagenet(let quote), .mayachain(let quote):
            guard let slippageBps = quote.slippageBps else { return nil }
            return Decimal(slippageBps) / 10000
        case .oneinch, .kyberswap, .lifi:
            return nil
        case .swapkit(let response, _, _):
            guard let impact = response.meta.priceImpact else { return nil }
            return Decimal(impact)
        }
    }

    var totalFees: String? {
        switch self {
        case .thorchain(let quote), .thorchainChainnet(let quote), .thorchainStagenet(let quote), .mayachain(let quote):
            return quote.fees.total
        case .oneinch, .kyberswap, .lifi, .swapkit:
            return nil
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .thorchain(let quote):
            hasher.combine(quote)
        case .thorchainChainnet(let quote):
            hasher.combine(quote)
        case .thorchainStagenet(let quote):
            hasher.combine(quote)
        case .mayachain(let quote):
            hasher.combine(quote)
        case .oneinch(let quote, let fee):
            hasher.combine(quote)
            hasher.combine(fee)
        case .kyberswap(let quote, let fee):
            hasher.combine(quote)
            hasher.combine(fee)
        case .lifi(let quote, let fee, let integratorFee):
            hasher.combine(quote)
            hasher.combine(fee)
            hasher.combine(integratorFee)
        case .swapkit(let response, let fee, let subProvider):
            hasher.combine(response)
            hasher.combine(fee)
            hasher.combine(subProvider)
        }
    }
}
