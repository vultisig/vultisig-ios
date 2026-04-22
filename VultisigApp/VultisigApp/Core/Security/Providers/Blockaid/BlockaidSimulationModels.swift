//
//  BlockaidSimulationModels.swift
//  VultisigApp
//

import Foundation
import BigInt

// MARK: - EVM Simulation Request

/// Mirrors the vultisig-windows extension payload for the Blockaid EVM
/// simulation endpoint: a JSON-RPC `eth_sendTransaction` call inside `data`,
/// with no `account_address` or `simulate_with_estimated_gas` fields.
struct EthereumSimulateTransactionRequestJson: Codable {
    let data: DataJson
    let chain: String
    let metadata: MetadataJson
    let options: [String]

    struct MetadataJson: Codable {
        let domain: String
    }

    struct DataJson: Codable {
        let method: String
        let params: [ParamsJson]

        struct ParamsJson: Codable {
            let from: String
            let to: String
            let value: String
            let data: String
        }
    }
}

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

    /// Human-readable from-side amount (e.g. "1.25"). For both transfer and
    /// swap simulations.
    var heroAmountText: String {
        fromAmountDecimal.formatForDisplay()
    }

    /// The "to" side of a swap simulation. Nil for transfer.
    var toCoin: BlockaidSimulationCoin? {
        if case .swap(_, let coin, _, _) = self { return coin }
        return nil
    }

    var toAmount: BigInt? {
        if case .swap(_, _, _, let amount) = self { return amount }
        return nil
    }

    var toAmountDecimal: Decimal? {
        guard let toAmount, let toCoin else { return nil }
        return toAmount.description.toDecimal() / pow(Decimal(10), toCoin.decimals)
    }

    var heroToAmountText: String? {
        toAmountDecimal?.formatForDisplay()
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

// MARK: - Solana Simulation Response

/// Solana simulation response from `/solana/message/scan` when invoked with
/// `options: ["simulation"]`. Top-level shape matches the validation response
/// (`result: { ... }`), with simulation data under `result.simulation`.
struct BlockaidSolanaSimulationResponseJson: Codable {
    let result: BlockaidSolanaSimulationResultJson?
    let status: String?
    let error: String?

    struct BlockaidSolanaSimulationResultJson: Codable {
        let simulation: BlockaidSolanaSimulationJson?
    }
}

/// Mirrors `BlockaidSolanaSimulation` in
/// `core-chain/security/blockaid/tx/simulation/api/core.ts`. Note the
/// intentional divergences from EVM: `account_assets_diff` (singular "diff")
/// instead of `assets_diffs`, and `in` / `out` as single nullable objects
/// rather than arrays.
struct BlockaidSolanaSimulationJson: Codable {
    let accountSummary: AccountSummary?

    enum CodingKeys: String, CodingKey {
        case accountSummary = "account_summary"
    }

    struct AccountSummary: Codable {
        let accountAssetsDiff: [AccountAssetDiff]?

        enum CodingKeys: String, CodingKey {
            case accountAssetsDiff = "account_assets_diff"
        }
    }

    struct AccountAssetDiff: Codable {
        let asset: Asset
        let assetType: String?
        let `in`: BalanceChange?
        let out: BalanceChange?

        enum CodingKeys: String, CodingKey {
            case asset
            case assetType = "asset_type"
            case `in`
            case out
        }
    }

    struct Asset: Codable {
        /// `"SOL"` for native SOL, `"TOKEN"` for SPL tokens.
        let type: String?
        let name: String?
        let symbol: String?
        /// Mint address for SPL tokens. Nil for native SOL (use the wrapped-SOL
        /// mint sentinel when rendering).
        let address: String?
        let decimals: Int?
        let logo: String?

        enum CodingKeys: String, CodingKey {
            case type
            case name
            case symbol
            case address
            case decimals
            case logo
        }
    }

    struct BalanceChange: Codable {
        let rawValue: String?

        enum CodingKeys: String, CodingKey {
            case rawValue = "raw_value"
        }
    }
}
