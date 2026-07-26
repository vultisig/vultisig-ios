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
    /// Jupiter Solana swap. `EVMQuote.tx.data` carries the base64 Solana wire
    /// transaction (mirrors the SwapKit-Solana shape). `platformFee` is the
    /// VULT-scaled affiliate fee in `toCoin` units — 0 when none is charged (the
    /// Ultimate tier), so a token-output swap still shows an explicit $0.00 row.
    /// `feeOnInput` is true only when the fee is collected on the INPUT mint —
    /// native-SOL (wrapped-SOL) outputs, where the amount can't be expressed in
    /// `toCoin` units — so `platformFee` is 0 there and callers suppress the
    /// affiliate row rather than render a misleading $0.00. Ranking is
    /// unaffected: it reads `outAmount`, already net of the fee.
    case jupiter(EVMQuote, fee: BigInt?, platformFee: Decimal, feeOnInput: Bool)

    /// True for the native-protocol routes (THORChain on any network, MayaChain)
    /// that deposit into a THOR/Maya inbound vault, so a source-chain halt can
    /// strand funds. Aggregator routes (1inch/LI.FI/KyberSwap/SwapKit) never
    /// deposit into those vaults, so the halt gate must not apply to them.
    var isNativeProtocolRoute: Bool {
        switch self {
        case .thorchain, .thorchainChainnet, .thorchainStagenet, .mayachain:
            return true
        case .oneinch, .kyberswap, .lifi, .swapkit, .jupiter:
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
        case .jupiter:
            return .jupiter
        }
    }

    /// Payload-free provider identity — the single source of truth for this
    /// quote's brand logo and display name. Network variants collapse to their
    /// base kind; `displayName` re-adds the `-Chainnet`/`-Stagenet` suffix.
    var kind: SwapProviderKind {
        switch self {
        case .thorchain, .thorchainChainnet, .thorchainStagenet:
            return .thorchain
        case .mayachain:
            return .maya
        case .oneinch:
            return .oneInch
        case .kyberswap:
            return .kyberSwap
        case .lifi:
            return .lifi
        case .swapkit:
            return .swapkit
        case .jupiter:
            return .jupiter
        }
    }

    var router: String? {
        switch self {
        case .thorchain(let quote), .thorchainChainnet(let quote), .thorchainStagenet(let quote), .mayachain(let quote):
            return quote.router
        case .oneinch(let quote, _),
                .lifi(let quote, _, _),
                .kyberswap(let quote, _),
                .jupiter(let quote, _, _, _):
            return quote.tx.to
        case .swapkit(let response, _, _):
            return response.targetAddress
        }
    }

    var totalSwapSeconds: Int? {
        switch self {
        case .thorchain(let quote), .thorchainChainnet(let quote), .thorchainStagenet(let quote), .mayachain(let quote):
            return quote.totalSwapSeconds
        case .oneinch, .kyberswap, .lifi, .swapkit, .jupiter:
            return nil
        }
    }

    var inboundAddress: String? {
        switch self {
        case .thorchain(let quote), .thorchainChainnet(let quote), .thorchainStagenet(let quote), .mayachain(let quote):
            return quote.inboundAddress
        case .oneinch(let quote, _),
                .lifi(let quote, _, _),
                .kyberswap(let quote, _),
                .jupiter(let quote, _, _, _):
            return quote.tx.to
        case .swapkit(let response, _, _):
            return response.inboundAddress ?? response.targetAddress
        }
    }

    var displayName: String? {
        switch self {
        // Network variants keep their suffix on top of the base brand name; the
        // sub-provider (e.g. Chainflip on SwapKit) stays on the payload for
        // routing/explorer links, so the display name stays the clean brand.
        case .thorchainChainnet:
            return "\(kind.displayName)-Chainnet"
        case .thorchainStagenet:
            return "\(kind.displayName)-Stagenet"
        default:
            return kind.displayName
        }
    }

    /// Brand-logo asset name for the provider (in `Crypto/`). Sourced from the
    /// shared `SwapProviderKind`, so it can't drift from Transaction History.
    var providerLogo: String {
        kind.providerLogo
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
        case .jupiter(_, _, let platformFee, _):
            // Jupiter's affiliate platform fee is already denominated in toCoin
            // units (0 when none is charged or the fee is taken on the input mint).
            return platformFee
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

    /// Source-chain gas cost in native wei (`gas × gasPrice`) for same-chain EVM
    /// aggregator quotes. Used only as a tie-break among in-band quotes that both
    /// expose it — same-unit source-native wei, no cross-asset price normalization.
    /// `nil` for THORChain/Maya/SwapKit, which expose no router gas at quote time.
    var sourceGasWei: BigInt? {
        switch self {
        case .oneinch(let quote, _), .kyberswap(let quote, _), .lifi(let quote, _, _):
            guard let gasPrice = BigInt(quote.tx.gasPrice), gasPrice > 0 else { return nil }
            return BigInt(quote.tx.gas) * gasPrice
        case .thorchain, .thorchainChainnet, .thorchainStagenet, .mayachain, .swapkit, .jupiter:
            return nil
        }
    }

    /// Route gas (`quote.tx.gas`) for EVM aggregator/SwapKit quotes — the gas
    /// input to the signed reconciliation (`EVMSwapFee`: oracle gas-limit floor
    /// plus the 600k zero-gas fallback). SwapKit carries it as a hex string on
    /// the wire; an unparseable or absent value surfaces as zero so the
    /// calculator's fallback applies, matching what the payload builder bakes
    /// into the signed quote. `nil` for THORChain/Maya, non-EVM SwapKit
    /// sources, and Jupiter (Solana), which expose no EVM route gas at quote
    /// time.
    var evmRouteGas: BigInt? {
        switch self {
        case .oneinch(let quote, _), .kyberswap(let quote, _), .lifi(let quote, _, _):
            return BigInt(quote.tx.gas)
        case .swapkit(let response, _, _):
            guard case .evm(let tx) = response.tx else { return nil }
            return BigInt(tx.gas.stripHexPrefix(), radix: 16) ?? .zero
        case .thorchain, .thorchainChainnet, .thorchainStagenet, .mayachain, .jupiter:
            return nil
        }
    }

    /// Gas price the provider priced the route at, in wei. The signer bumps it
    /// against the oracle's `maxFeePerGas` (see `EVMSwapFee`), so displays must
    /// feed it through the same reconciliation. `EVMQuote.tx.gasPrice` is a
    /// decimal string; SwapKit's wire `tx.gasPrice` is hex. `nil` for routes
    /// with no EVM gas price at quote time.
    var evmQuoteGasPriceWei: BigInt? {
        switch self {
        case .oneinch(let quote, _), .kyberswap(let quote, _), .lifi(let quote, _, _):
            return EVMSwapFee.quoteGasPriceWei(quote.tx.gasPrice)
        case .swapkit(let response, _, _):
            guard case .evm(let tx) = response.tx else { return nil }
            return BigInt(tx.gasPrice.stripHexPrefix(), radix: 16) ?? .zero
        case .thorchain, .thorchainChainnet, .thorchainStagenet, .mayachain, .jupiter:
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
        case .oneinch, .kyberswap, .lifi, .swapkit, .jupiter:
            return nil
        }
    }

    var priceImpact: Decimal? {
        switch self {
        case .thorchain(let quote), .thorchainChainnet(let quote), .thorchainStagenet(let quote), .mayachain(let quote):
            guard let slippageBps = quote.slippageBps else { return nil }
            return Decimal(slippageBps) / 10000
        case .oneinch, .kyberswap, .lifi, .jupiter:
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
        case .oneinch, .kyberswap, .lifi, .swapkit, .jupiter:
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
        case .jupiter(let quote, let fee, let platformFee, let feeOnInput):
            hasher.combine(quote)
            hasher.combine(fee)
            hasher.combine(platformFee)
            hasher.combine(feeOnInput)
        }
    }
}
