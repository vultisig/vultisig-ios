//
//  SwapPayload.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 10.05.2024.
//

import Foundation
import BigInt

enum SwapPayload: Codable, Hashable { // TODO: Merge with SwapQuote
    case thorchain(THORChainSwapPayload)
    case thorchainChainnet(THORChainSwapPayload)
    case thorchainStagenet(THORChainSwapPayload)
    case mayachain(THORChainSwapPayload)
    case generic(GenericSwapPayload)
    /// SwapKit non-EVM-shaped routes (BTC PSBT today; TRON/TON/SUI/Cardano
    /// in later phases). EVM and Solana SwapKit swaps still ride `.generic`
    /// since their wire shape matches `OneInchSwapPayload` 1:1.
    case swapkit(SwapKitSwapPayload)

    var fromCoin: Coin {
        switch self {
        case .thorchain(let payload), .thorchainChainnet(let payload), .thorchainStagenet(let payload), .mayachain(let payload):
            return payload.fromCoin
        case .generic(let payload):
            return payload.fromCoin
        case .swapkit(let payload):
            return payload.fromCoin
        }
    }

    var toCoin: Coin {
        switch self {
        case .thorchain(let payload), .thorchainChainnet(let payload), .thorchainStagenet(let payload), .mayachain(let payload):
            return payload.toCoin
        case .generic(let payload):
            return payload.toCoin
        case .swapkit(let payload):
            return payload.toCoin
        }
    }

    var fromAmount: BigInt {
        switch self {
        case .thorchain(let payload), .thorchainChainnet(let payload), .thorchainStagenet(let payload), .mayachain(let payload):
            return payload.fromAmount
        case .generic(let payload):
            return payload.fromAmount
        case .swapkit(let payload):
            return payload.fromAmount
        }
    }

    var toAmountDecimal: Decimal {
        switch self {
        case .thorchain(let payload), .thorchainChainnet(let payload), .thorchainStagenet(let payload), .mayachain(let payload):
            return payload.toAmountDecimal
        case .generic(let payload):
            return payload.toAmountDecimal
        case .swapkit(let payload):
            return payload.toAmountDecimal
        }
    }

    var router: String? {
        switch self {
        case .thorchain(let payload), .thorchainChainnet(let payload), .thorchainStagenet(let payload), .mayachain(let payload):
            return payload.routerAddress
        case .generic(let payload):
            return payload.quote.tx.to
        case .swapkit(let payload):
            return payload.targetAddress
        }
    }

    /// True for the native-protocol routes (THORChain on any network, MayaChain)
    /// whose signed memo carries a `LIM` output floor. Mirrors
    /// `SwapQuote.isNativeProtocolRoute` for the co-signer, which sees only the
    /// serialized payload. Aggregator routes (1inch / LI.FI / KyberSwap /
    /// Jupiter / SwapKit) sign opaque calldata or a pre-built transaction, so
    /// whatever floor they enforce is not readable here.
    var isNativeProtocolRoute: Bool {
        switch self {
        case .thorchain, .thorchainChainnet, .thorchainStagenet, .mayachain:
            return true
        case .generic, .swapkit:
            return false
        }
    }

    /// Price impact of the route as a fraction (`0.0125` == 1.25%), mirroring
    /// `SwapQuote.priceImpact` for the co-signer, which holds only the serialized
    /// payload. Native routes carry the quote's basis points on the wire; the
    /// aggregator routes put none there. `nil` also for a sender that pre-dates
    /// the field — consumers hide the row rather than claim a zero-impact route,
    /// which a carried `0` would legitimately mean.
    /// "SwapKit (NEAR)" when a route tag travelled with the payload, the bare
    /// aggregator name when it did not. A tag naming the aggregator itself is
    /// dropped rather than repeated: SwapKit's `providers` is empty for some
    /// routes and its own name is the fallback, which would otherwise read
    /// "SwapKit (SwapKit)".
    private static func appendingRoute(_ provider: String, subProvider: String?) -> String {
        guard let subProvider = subProvider?.nilIfEmpty,
              subProvider.caseInsensitiveCompare(provider) != .orderedSame else {
            return provider
        }
        return "\(provider) (\(subProvider))"
    }

    var priceImpact: Decimal? {
        switch self {
        case .thorchain(let payload), .thorchainChainnet(let payload),
             .thorchainStagenet(let payload), .mayachain(let payload):
            guard let slippageBps = payload.slippageBps else { return nil }
            return Decimal(slippageBps) / 10000
        case .generic, .swapkit:
            return nil
        }
    }

    var isDeposit: Bool {
        switch self {
        case .mayachain(let payload):
            return payload.fromCoin.chain == .mayaChain && payload.toCoin.chain == .thorChain
        case .generic, .thorchain, .thorchainChainnet, .thorchainStagenet, .swapkit:
            return false
        }
    }

    /// Persisted / explorer-facing provider identity. Transaction History stores
    /// this string and `ExplorerLinkBuilder` resolves it back to a tracker URL
    /// through an exact alias lookup, so the route tag lives on
    /// `providerDisplayName` instead of here: `"SwapKit (CHAINFLIP)"` normalizes
    /// to `swapkitchainflip`, which is in no alias table, and the row silently
    /// falls back to the chain explorer instead of the aggregator's tracker.
    var providerName: String {
        switch self {
        case .thorchain:
            return "THORChain"
        case .thorchainChainnet:
            return "THORChain-Chainnet"
        case .thorchainStagenet:
            return "THORChain-Stagenet"
        case .mayachain:
            return "Maya Protocol"
        case .generic(let payload):
            return payload.provider.name
        case .swapkit:
            return "SwapKit"
        }
    }

    /// Verify-screen name: the aggregator plus the route it actually took, when
    /// a route tag travelled with the payload. SwapKit's EVM and Solana routes
    /// ride `.generic`, so this is what lets a co-signer name them the way every
    /// other SwapKit route is already named.
    ///
    /// Kept separate from `providerName` deliberately. That string is persisted
    /// to Transaction History and aliased back to a tracker URL by
    /// `ExplorerLinkBuilder`, whose lookup is exact — folding a route tag into it
    /// would drop the aggregator's own tracker for every affected row.
    var providerDisplayName: String {
        switch self {
        case .generic(let payload):
            return Self.appendingRoute(payload.provider.name, subProvider: payload.subProvider)
        case .swapkit(let payload):
            // Preserves the verify-screen "via Chainflip" / "via NEAR Intents" /
            // "via Garden" affordance this shape has always had.
            return Self.appendingRoute("SwapKit", subProvider: payload.subProvider)
        case .thorchain, .thorchainChainnet, .thorchainStagenet, .mayachain:
            return providerName
        }
    }
}
