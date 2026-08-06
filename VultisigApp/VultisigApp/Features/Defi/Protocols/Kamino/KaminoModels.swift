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
        /// Base units of the **underlying token**. Correctly denominated, unlike
        /// `minWithdrawAmount` — but still not a figure the program accepts: a
        /// deposit at exactly this amount is refused. Only
        /// `KaminoService.effectiveMinimumDeposit` may read it.
        let minDepositAmount: String
        /// Base units of the **underlying token**, despite naming the unit the
        /// withdraw endpoint takes. Reading it as a share count is a silent
        /// error on a dollar vault (the rate is near 1) and a ~930× one on the
        /// SOL vault. It is also not the floor the program enforces — see
        /// `KaminoService.effectiveMinimumWithdraw`, which is what the form
        /// should use. Nothing but that derivation may read this field.
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
    /// A vault was described to the service in terms the registry does not
    /// recognise. The curated entry is the app's record of a vault's identity;
    /// anything else cannot be used to size or target a transaction.
    case vaultNotInRegistry(String)
    /// The API described a vault differently from the registry. Mints, their
    /// decimals and the farm are immutable properties of a kVault, so a
    /// disagreement is either the wrong vault or a response that cannot be
    /// trusted to size or target a transaction.
    case vaultMetadataMismatch(field: String, expected: String, actual: String)
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
        case .vaultNotInRegistry(let address):
            return "Vault \(address) is not one this app transacts with"
        case .vaultMetadataMismatch(let field, let expected, let actual):
            return "Kamino reported \(field) as \(actual); this vault's is \(expected)"
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
    /// The smallest deposit the form may offer.
    ///
    /// DERIVED: the published `minDepositAmount` plus a margin, because the
    /// program refuses a deposit at exactly the published figure. See
    /// `KaminoService.effectiveMinimumDeposit`.
    let minDeposit: KaminoTokenAmount
    /// The smallest withdraw the form may offer, in SHARE base units.
    ///
    /// DERIVED, not `state.minWithdrawAmount` read at face value: that field is
    /// denominated in the underlying token and the program's own floor is higher
    /// than it. `KaminoService.effectiveMinimumWithdraw` holds the measurements
    /// and the reasoning. Because the derivation goes through `tokensPerShare`,
    /// this figure moves with the rate, and it is hydrated in the same response.
    let minWithdraw: KaminoShareAmount
    /// The address lookup table the built transactions reference.
    ///
    /// Live rather than pinned: unlike the mints and the farm, Kamino can
    /// legitimately repoint a vault at a new table. It is also the one live
    /// field a transaction check does not rest on — a table only decides which
    /// pubkey an account index *names*, and every account that matters is
    /// compared against a locally derived value, so a substituted table renames
    /// an account into a mismatch rather than out of one.
    let lookupTable: String
    /// 30-day APY as a fraction (0.0391 = 3.91%). Display-only, so `Decimal` is
    /// fine here.
    let apy30d: Decimal
    /// Underlying tokens per share, kept exact: this rate sizes a withdraw, and
    /// a rounding error in it can over-request shares.
    let tokensPerShare: KaminoRate
    let tokenPriceUsd: Decimal
    /// The underlying balance the vault currently holds liquid, rather than
    /// invested in lending reserves. `nil` when the metrics response did not
    /// carry a readable value.
    ///
    /// Advisory only — it says what a withdraw is likely to be able to settle
    /// immediately, and nothing sizes a transaction from it. The measured ratio
    /// is 0.36% of the Steakhouse vault and 0.04% of the Allez vault, so a
    /// withdraw above this buffer is the ordinary case, not an exception.
    let tokensAvailable: KaminoTokenAmount?

    init(
        descriptor: KaminoVaultDescriptor,
        name: String,
        minDeposit: KaminoTokenAmount,
        minWithdraw: KaminoShareAmount,
        lookupTable: String,
        apy30d: Decimal,
        tokensPerShare: KaminoRate,
        tokenPriceUsd: Decimal,
        tokensAvailable: KaminoTokenAmount? = nil
    ) {
        self.descriptor = descriptor
        self.name = name
        self.minDeposit = minDeposit
        self.minWithdraw = minWithdraw
        self.lookupTable = lookupTable
        self.apy30d = apy30d
        self.tokensPerShare = tokensPerShare
        self.tokenPriceUsd = tokenPriceUsd
        self.tokensAvailable = tokensAvailable
    }

    var id: String { descriptor.address }

    // The vault's identity is read from the registry, never from the response.
    // A transaction built by the API cannot be validated against values the same
    // API supplied.
    var tokenMint: String { descriptor.tokenMint }
    var tokenDecimals: Int { descriptor.tokenDecimals }
    var sharesMint: String { descriptor.sharesMint }
    var shareDecimals: Int { descriptor.sharesDecimals }
    var farm: String? { descriptor.farm }

    /// `true` when deposits auto-stake into a farm, so the shares are not visible
    /// as a wallet token.
    var hasFarm: Bool { farm != nil }

    /// A vault whose underlying token is wrapped SOL. Its deposits carry a
    /// wrap prefix — create the wSOL account, transfer lamports, sync — that no
    /// other vault emits.
    var isWrappedSolVault: Bool { tokenMint == KaminoVaultRegistry.wrappedSolMint }
}
