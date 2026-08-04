//
//  KaminoModels.swift
//  VultisigApp
//

import Foundation

// MARK: - Reads

/// `GET /kvaults/vaults/{address}`.
struct KaminoVaultStateResponse: Decodable {
    let address: String
    let programId: String
    let state: State

    struct State: Decodable {
        let name: String
        let tokenMint: String
        let tokenMintDecimals: Int
        let sharesMint: String
        /// Share decimals are independent of token decimals — across the live
        /// vault set the pairs include (6,6), (6,9), (8,8) and (9,9). Never
        /// assume they match.
        let sharesMintDecimals: Int
        /// Base units of the **underlying token**.
        let minDepositAmount: String
        /// Base units of **shares**, not of the token. A user-entered token
        /// amount must be converted before it is compared against this.
        let minWithdrawAmount: String
        /// Address lookup table the built transactions reference.
        let vaultLookupTable: String
        /// When set, deposits auto-stake the shares into this farm and they never
        /// appear in the user's associated token account.
        let vaultFarm: String
        let performanceFeeBps: Int
        let managementFeeBps: Int
    }
}

/// `GET /kvaults/vaults/{address}/metrics`. Every numeric field is a decimal
/// string; APYs are fractions (`"0.0391"` = 3.91%), not percentages.
struct KaminoVaultMetricsResponse: Decodable {
    let apy30d: String
    /// Underlying tokens per share — the rate for valuing a position.
    let tokensPerShare: String
    /// USD per share. NOT interchangeable with `tokensPerShare`.
    let sharePrice: String
    let tokenPrice: String
    let tokensAvailable: String
    let tokensInvested: String
}

/// One element of `GET /kvaults/users/{owner}/positions`. Shares only — the
/// endpoint returns no token or fiat value.
struct KaminoUserPositionResponse: Decodable {
    let vaultAddress: String
    /// Shares held inside the vault's farm. For a farmed vault this is where a
    /// deposit lands, so it is normally the whole position.
    let stakedShares: String
    /// Shares sitting in the user's associated token account.
    let unstakedShares: String
    let totalShares: String
}

/// `GET /kvaults/users/{owner}/vaults/{vault}/pnl`.
struct KaminoPnlResponse: Decodable {
    let totalCostBasis: Amounts
    let totalPnl: Amounts

    struct Amounts: Decodable {
        let token: String
        let sol: String
        let usd: String
    }
}

// MARK: - Actions

/// Body for `POST /ktx/kvault/{deposit,withdraw}`. `amount` is a human-units
/// decimal string whose unit depends on the action: tokens for deposit, shares
/// for withdraw. The typed builders on `KaminoService` are the only intended way
/// to construct this.
struct KaminoActionRequest: Encodable {
    let wallet: String
    let kvault: String
    let amount: String
}

struct KaminoActionResponse: Decodable {
    /// Base64 unsigned transaction, ready to validate, budget and keysign.
    let transaction: String
}

/// Error body the API returns with a 400.
struct KaminoErrorResponse: Decodable {
    let statusCode: Int
    let message: String
    let error: String
    let code: String?
}

// MARK: - Errors

enum KaminoServiceError: Error, LocalizedError, Equatable {
    /// A structured error from the API. `status` is retained alongside the
    /// machine-readable `code` (`KVAULT_NOT_FOUND`, `TRANSACTION_SIZE_ERROR`, …)
    /// so callers can still tell a permanent 400 from a retryable 429/5xx that
    /// happened to carry the same body shape.
    case api(status: Int, code: String?, message: String)
    /// A numeric field did not parse under the strict decimal rules.
    case malformedNumber(field: String, value: String)
    /// An amount could not be sent: non-positive, beyond the `u64` an on-chain
    /// instruction can carry, or at an implausible decimal scale.
    case invalidAmount(String)
    /// A share/token conversion could not be performed (non-positive rate).
    case conversionFailed

    /// Whether retrying the same request could plausibly succeed.
    var isRetryable: Bool {
        guard case .api(let status, _, _) = self else { return false }
        return status == 429 || (500...599).contains(status)
    }

    var errorDescription: String? {
        switch self {
        case .api(_, let code, let message):
            return code.map { "\($0): \(message)" } ?? message
        case .malformedNumber(let field, let value):
            return "Malformed Kamino number for \(field): \(value)"
        case .invalidAmount(let detail):
            return "Invalid Kamino amount: \(detail)"
        case .conversionFailed:
            return "Kamino share conversion failed"
        }
    }
}

// MARK: - Hydrated vault

/// A launch vault after its registry entry has been merged with live API state
/// and metrics. This is what the feature layer consumes; the raw responses stay
/// at the service boundary.
struct KaminoVaultInfo: Hashable, Identifiable {
    let descriptor: KaminoVaultDescriptor
    /// On-chain vault name (`"Steakhouse USDC"`).
    let name: String
    let tokenMint: String
    let tokenDecimals: Int
    let sharesMint: String
    let shareDecimals: Int
    let minDeposit: KaminoTokenAmount
    let minWithdraw: KaminoShareAmount
    let lookupTable: String
    /// `true` when deposits auto-stake into a farm, so the shares are not visible
    /// as a wallet token.
    let hasFarm: Bool
    /// 30-day APY as a fraction (0.0391 = 3.91%). Display-only, so `Decimal` is
    /// fine here.
    let apy30d: Decimal
    /// Underlying tokens per share, kept exact: this rate sizes a withdraw, and
    /// a rounding error in it can over-request shares.
    let tokensPerShare: KaminoRate
    let tokenPriceUsd: Decimal

    var id: String { descriptor.address }
}
