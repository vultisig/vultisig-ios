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

    var isDeposit: Bool {
        switch self {
        case .mayachain(let payload):
            return payload.fromCoin.chain == .mayaChain && payload.toCoin.chain == .thorChain
        case .generic, .thorchain, .thorchainChainnet, .thorchainStagenet, .swapkit:
            return false
        }
    }

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
        case .swapkit(let payload):
            // Sub-provider tag preserves the verify-screen "via Chainflip" /
            // "via NEAR Intents" / "via Garden" affordance.
            return payload.subProvider.isEmpty ? "SwapKit" : "SwapKit (\(payload.subProvider))"
        }
    }
}
