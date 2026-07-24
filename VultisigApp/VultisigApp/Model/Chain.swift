//
//  Chain.swift
//  VultisigApp

import Foundation
import SwiftData

enum Chain: String, Codable, Hashable, CaseIterable {
    case thorChain
    case thorChainChainnet
    case thorChainStagenet
    case solana
    case ethereum
    case avalanche
    case base
    case blast
    case arbitrum
    case polygon
    case polygonV2
    case optimism
    case bscChain
    case bitcoin
    case bitcoinCash
    case litecoin
    case dogecoin
    case dash
    case cardano
    case gaiaChain
    case kujira
    case mayaChain
    case cronosChain
    case sui
    case polkadot
    case zksync
    case dydx
    case ton
    case osmosis
    case terra
    case terraClassic
    case noble
    case ripple
    case akash
    case tron
    case ethereumSepolia
    case zcash
    case mantle
    case hyperliquid
    case sei
    case qbtc
    case bittensor

    /// Maps removed chain raw values to their replacement chain.
    /// This prevents SwiftData from crashing when decoding legacy persisted data.
    private static let removedChainMigrations: [String: Chain] = [
        "thorChainStagenet2": .thorChainStagenet,
        "thorChainChainnet": .thorChain,
        "polygon": .polygonV2,
    ]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        if let chain = Chain(rawValue: rawValue) {
            self = chain
        } else if let migrated = Chain.removedChainMigrations[rawValue] {
            self = migrated
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot initialize Chain from invalid String value \(rawValue)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    enum MigrationKeys: String, CodingKey {
        case ticker
    }

    var signingKeyType: KeyType {
        if self == .qbtc {
            return .MLDSA
        }
        switch chainType {
        case .Cosmos, .EVM, .THORChain, .UTXO, .Ripple, .Tron:
            return .ECDSA
        case .Solana, .Polkadot, .Sui, .Ton, .Cardano:
            return .EdDSA
        }
    }

    var isECDSA: Bool {
        return signingKeyType == .ECDSA
    }

    var index: Int {
        return Chain.allCases.firstIndex(of: self) ?? 0
    }

    static let example = Chain(name: "Bitcoin")!

    var isSwapAvailable: Bool {
        switch self {
        case .thorChain,
             .thorChainChainnet,
             .thorChainStagenet,
             .mayaChain,
             .gaiaChain,
             .kujira,
             .bitcoin,
             .dogecoin,
             .bitcoinCash,
             .litecoin,
             .dash,
             .ripple,
             .avalanche,
             .base,
             .bscChain,
             .ethereum,
             .optimism,
             .polygon,
             .arbitrum,
             .blast,
             .cronosChain,
             .solana,
             .zksync,
             .zcash,
             .mantle,
             .hyperliquid,
             .tron,
             .cardano,
             .sui,
             .ton,
             .polygonV2:
            return true
        case .polkadot,
             .dydx,
             .osmosis,
             .terra,
             .terraClassic,
             .noble,
             .akash,
             .ethereumSepolia,
             .sei,
             .qbtc,
             .bittensor:
            return false
        }
    }

    /// Whether the fiat on-ramp (Buy) flow is offered for this chain. QBTC has
    /// no on-ramp provider, so Buy is hidden; every other chain keeps the
    /// existing behaviour.
    var isBuyAvailable: Bool {
        self != .qbtc
    }

    /// Cosmos-SDK native staking via delegate / undelegate / redelegate /
    /// claim-rewards. Only the LUNA / LUNC chains today; other Cosmos
    /// chains (gaia / kujira / osmosis / etc.) are out of scope for the
    /// in-app staking UI.
    var isCosmosStakingChain: Bool {
        switch self {
        case .terra, .terraClassic, .qbtc:
            return true
        default:
            return false
        }
    }

    /// Solana native staking via the on-chain Stake program (delegate /
    /// deactivate / withdraw). Only Solana today.
    var isSolanaStakingChain: Bool {
        self == .solana
    }
}

extension Chain {
    var supportsEip1559: Bool {
        switch self {
        case .bscChain:
            return false
        case .ethereum, .avalanche, .arbitrum, .base, .optimism, .polygon, .polygonV2, .blast, .cronosChain, .ethereumSepolia, .mantle, .hyperliquid, .sei:
            return true
        default:
            return true
        }
    }

    /// Indicates if this chain supports pending transaction tracking via sequence numbers (nonce)
    var supportsPendingTransactions: Bool {
        switch self {
        case .thorChain, .thorChainChainnet, .thorChainStagenet, .mayaChain, .gaiaChain, .kujira, .osmosis, .dydx, .terra, .terraClassic, .noble, .akash, .qbtc:
            return true
        default:
            return false
        }
    }

    /// Whether the Send flow's memo input should be exposed for this chain.
    /// Most chains carry a memo at the protocol level. The exception is Sui:
    /// a transaction is a Programmable Transaction Block with no memo field, so
    /// a typed memo would be silently dropped — hiding the input avoids that.
    /// Cardano DOES support memos: they are attached on-chain as CIP-20
    /// transaction metadata (label 674) via `CardanoSigningInput.auxiliaryData`.
    var supportsMemo: Bool {
        switch self {
        case .sui:
            return false
        default:
            return true
        }
    }

    /// Whether the Send flow's Destination Tag input should be exposed for
    /// this chain. XRPL payments carry an optional 32-bit tag that custodial
    /// services (exchanges) require to credit deposits to the right account —
    /// only Ripple supports it.
    var supportsDestinationTag: Bool {
        self == .ripple
    }

    static var keyImportEnabledChains: [Chain] {
        allCases.filter {
            switch $0 {
            case .cardano, .thorChainChainnet, .thorChainStagenet, .polygonV2, .qbtc:
                return false
            default:
                return true
            }
        }
    }
}
