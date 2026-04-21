//
//  BlockaidSimulationModels.swift
//  VultisigApp
//

import Foundation
import BigInt

// MARK: - Parsed Simulation Info

/// Authoritative balance-change information derived from a Blockaid simulation.
///
/// The parsed form intentionally mirrors the vultisig-windows model so the dApp
/// hero can promote a `send` / `swap.fromCoin` / `transfer.fromCoin` branch to
/// the primary display instead of the front-runnable 4byte title.
enum BlockaidSimulationInfo: Equatable {
    case transfer(fromCoin: BlockaidSimulationCoin, fromAmount: BigInt)
    case swap(
        fromCoin: BlockaidSimulationCoin,
        toCoin: BlockaidSimulationCoin,
        fromAmount: BigInt,
        toAmount: BigInt
    )

    var fromCoin: BlockaidSimulationCoin {
        switch self {
        case .transfer(let coin, _):
            return coin
        case .swap(let coin, _, _, _):
            return coin
        }
    }

    var fromAmount: BigInt {
        switch self {
        case .transfer(_, let amount):
            return amount
        case .swap(_, _, let amount, _):
            return amount
        }
    }

    var fromAmountDecimal: Decimal {
        fromAmount.description.toDecimal() / pow(Decimal(10), fromCoin.decimals)
    }

    var heroAmountText: String {
        fromAmountDecimal.formatForDisplay()
    }
}

struct BlockaidSimulationCoin: Equatable {
    let chain: Chain
    let address: String?
    let ticker: String
    let logo: String
    let decimals: Int
}

// MARK: - EVM Simulation Response

struct BlockaidEvmSimulationResponseJson: Codable {
    let simulation: BlockaidEvmSimulationJson?
    let validation: BlockaidTransactionScanResponseJson.BlockaidValidationJson?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case simulation
        case validation
        case error
    }
}

struct BlockaidEvmSimulationJson: Codable {
    let status: String?
    let accountSummary: AccountSummary?

    enum CodingKeys: String, CodingKey {
        case status
        case accountSummary = "account_summary"
    }

    struct AccountSummary: Codable {
        let assetsDiffs: [AssetDiff]?

        enum CodingKeys: String, CodingKey {
            case assetsDiffs = "assets_diffs"
        }
    }

    struct AssetDiff: Codable {
        let asset: Asset
        let assetType: String?
        let `in`: [BalanceChange]?
        let out: [BalanceChange]?

        enum CodingKeys: String, CodingKey {
            case asset
            case assetType = "asset_type"
            case `in`
            case out
        }
    }

    struct Asset: Codable {
        let type: String?
        let decimals: Int?
        let address: String?
        let logoUrl: String?
        let name: String?
        let symbol: String?

        enum CodingKeys: String, CodingKey {
            case type
            case decimals
            case address
            case logoUrl = "logo_url"
            case name
            case symbol
        }
    }

    struct BalanceChange: Codable {
        let rawValue: String?

        enum CodingKeys: String, CodingKey {
            case rawValue = "raw_value"
        }
    }
}
