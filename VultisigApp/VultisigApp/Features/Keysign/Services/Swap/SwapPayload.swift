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

    /// Route price impact as a fraction (`0.0125` == 1.25%). `nil` where no
    /// impact travelled; consumers hide the row rather than render a zero, which
    /// a carried `0` would legitimately mean.
    /// A tag naming the aggregator itself is dropped rather than repeated:
    /// SwapKit's `providers` can be empty and its own name is the fallback,
    /// which would otherwise read "SwapKit (SwapKit)".
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

    /// Persisted identity. Transaction History stores this string and
    /// `ExplorerLinkBuilder` resolves it to a tracker through an EXACT alias
    /// lookup, so a route tag must not be folded in here: "SwapKit (CHAINFLIP)"
    /// normalizes to `swapkitchainflip`, matches no alias, and the row silently
    /// loses its tracker. The tag lives on `providerDisplayName`.
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

    /// Verify-screen name. `.generic` deliberately does NOT render the route tag
    /// it carries: this device's initiator screen names the clean brand
    /// (`SwapQuote.displayName`), so rendering it here alone would describe one
    /// swap two ways. The tag travels for the clients that do render it.
    var providerDisplayName: String {
        switch self {
        case .swapkit(let payload):
            // Long-standing "via Chainflip" affordance for the transfer routes.
            return Self.appendingRoute("SwapKit", subProvider: payload.subProvider)
        case .generic, .thorchain, .thorchainChainnet, .thorchainStagenet, .mayachain:
            return providerName
        }
    }
}
