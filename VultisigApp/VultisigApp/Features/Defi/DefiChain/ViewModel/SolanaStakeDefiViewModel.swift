//
//  SolanaStakeDefiViewModel.swift
//  VultisigApp
//
//  Backs the Solana stake segment on the DeFi tab. Unlike Cosmos's
//  per-validator delegation list, Solana staking is per-STAKE-ACCOUNT: a wallet
//  holds N stake accounts, each delegating to exactly one validator with its own
//  activation lifecycle. So this VM produces one `SolanaStakeAccountRow` per
//  account — NOT a coin-keyed `StakePosition` `@Model` — folding in the live
//  epoch (for activation/cooldown state), validator metadata (name/logo), and a
//  resolved APY.
//
//  Stake accounts are read live (never long-cached) so a just-submitted
//  delegate/unstake/withdraw/move is visible on the next refresh. After a signed
//  keysign the caller invokes `invalidateAndRefresh(...)`, which additionally
//  drops the short-lived epoch cache so the post-tx state derivation is exact.
//
//  Data-layer counterpart to the position-card UI in `SolanaStakeDefiView`.
//

import Foundation
import Combine
import OSLog

@MainActor
final class SolanaStakeDefiViewModel: ObservableObject {
    @Published private(set) var rows: [SolanaStakeAccountRow] = []
    @Published private(set) var totalStaked: Decimal = 0
    @Published private(set) var rentReserve: Decimal = 0
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: String?

    private let stakingService: SolanaStakingServiceProtocol
    private let metadataProvider: ValidatorMetadataProvider
    private let apyResolver: SolanaStakingAPYResolverProtocol
    private let onInvalidateCaches: @Sendable () -> Void
    private let logger = Logger(
        subsystem: "com.vultisig.app",
        category: "solana-stake-defi-vm"
    )

    init(
        stakingService: SolanaStakingServiceProtocol = SolanaStakingService(),
        metadataProvider: ValidatorMetadataProvider = StakewizValidatorMetadataProvider(),
        apyResolver: SolanaStakingAPYResolverProtocol = SolanaStakingAPYResolver(),
        onInvalidateCaches: @escaping @Sendable () -> Void = { SolanaService.shared.invalidateEpochInfoCache() }
    ) {
        self.stakingService = stakingService
        self.metadataProvider = metadataProvider
        self.apyResolver = apyResolver
        self.onInvalidateCaches = onInvalidateCaches
    }

    /// Whether the vault currently has any delegated SOL — drives the
    /// empty-vs-populated branch in the view independently of the in-flight
    /// loading state.
    var hasPositions: Bool { !rows.isEmpty }

    /// Fans out the stake-account read (uncached), the live epoch, the cached
    /// validator set + inflation, and the rent reserve, then folds them into one
    /// row per stake account. Per-call failures degrade individually: a failed
    /// validator/metadata/inflation fetch renders rows with on-chain-only data
    /// and a nil APY rather than dropping the position.
    func refresh(owner: String, decimals: Int) async {
        isLoading = true
        defer { isLoading = false }
        error = nil

        async let stakeAccountsTask = fetchStakeAccounts(owner: owner)
        async let epochTask = fetchEpochInfo()
        async let validatorsTask = fetchValidators()
        async let inflationTask = fetchInflation()
        async let rentReserveTask = fetchRentReserve()

        let stakeAccounts = await stakeAccountsTask
        let epoch = await epochTask
        let validators = await validatorsTask
        let inflation = await inflationTask
        let reserveLamports = await rentReserveTask

        let divisor = pow(Decimal(10), decimals)
        rentReserve = Decimal(reserveLamports) / divisor

        let validatorsByVote = Dictionary(
            validators.map { ($0.votePubkey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let totalActivatedStake = validators
            .map { $0.activatedStake }
            .reduce(UInt64.zero, +)

        // Enrich validator metadata (name / logo / Stakewiz APY) for just the
        // vote accounts the user is delegated to. The provider never throws — an
        // outage yields an empty map and rows fall back to on-chain display.
        let votePubkeys = stakeAccounts.compactMap { $0.delegation?.votePubkey }
        let metadata = await metadataProvider.metadata(forVotePubkeys: votePubkeys)

        let currentEpoch = epoch?.epoch
        rows = stakeAccounts.map { account in
            row(
                for: account,
                divisor: divisor,
                currentEpoch: currentEpoch,
                validatorsByVote: validatorsByVote,
                metadata: metadata,
                inflation: inflation,
                totalActivatedStake: totalActivatedStake
            )
        }
        .sorted { $0.delegatedAmount > $1.delegatedAmount }

        totalStaked = rows.map(\.delegatedAmount).reduce(0, +)

        if rows.isEmpty {
            logger.info("No stake accounts for owner \(owner, privacy: .private)")
        }
    }

    /// Post-keysign refresh. Drops the short-lived epoch cache before re-reading
    /// so the activation/cooldown state reflects the just-submitted tx, then
    /// re-runs the row pipeline. Stake accounts are already uncached.
    func invalidateAndRefresh(owner: String, decimals: Int) async {
        onInvalidateCaches()
        await refresh(owner: owner, decimals: decimals)
    }

    // MARK: - Row building

    private func row(
        for account: SolanaStakeAccount,
        divisor: Decimal,
        currentEpoch: UInt64?,
        validatorsByVote: [String: SolanaValidator],
        metadata: [String: ValidatorMetadata],
        inflation: Double?,
        totalActivatedStake: UInt64
    ) -> SolanaStakeAccountRow {
        let delegation = account.delegation
        let votePubkey = delegation?.votePubkey
        var validator = votePubkey.flatMap { validatorsByVote[$0] }
        if let votePubkey, let meta = metadata[votePubkey] {
            validator?.metadata = meta
        }

        let delegatedLamports = delegation?.stake ?? 0
        let delegatedAmount = Decimal(delegatedLamports) / divisor

        let state: SolanaStakeActivationState
        if let currentEpoch {
            state = account.activationState(currentEpoch: currentEpoch)
        } else {
            // No epoch read — assume active when delegated so the row still
            // renders; the next refresh corrects the state once epoch is back.
            state = delegation == nil ? .inactive : .active
        }

        let apy: Decimal? = validator.flatMap { validator in
            apyResolver.apy(
                for: validator,
                metadataAPY: validator.metadata.apyEstimate,
                inflationRate: inflation,
                totalActivatedStake: totalActivatedStake,
                totalSupplyLamports: nil
            )
        }

        let validatorName = validator?.displayName
            ?? votePubkey.map { SolanaValidator.truncatedPubkey($0) }
            ?? SolanaValidator.truncatedPubkey(account.pubkey)

        return SolanaStakeAccountRow(
            stakeAccount: account,
            validatorName: validatorName,
            validatorVotePubkey: votePubkey,
            validatorLogoURL: validator?.logoURL,
            delegatedAmount: delegatedAmount,
            rentReserve: Decimal(account.rentExemptReserve) / divisor,
            activationState: state,
            apyPercent: apy
        )
    }

    // MARK: - Fetches (each degrades to a quiet default on failure)

    private func fetchStakeAccounts(owner: String) async -> [SolanaStakeAccount] {
        do {
            return try await stakingService.fetchStakeAccounts(owner: owner)
        } catch {
            logger.error("Failed to fetch stake accounts: \(error.localizedDescription, privacy: .public)")
            self.error = error.localizedDescription
            return []
        }
    }

    private func fetchEpochInfo() async -> SolanaEpochInfo? {
        do {
            return try await stakingService.fetchEpochInfo()
        } catch {
            logger.warning("Failed to fetch epoch info: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func fetchValidators() async -> [SolanaValidator] {
        do {
            return try await stakingService.fetchValidators()
        } catch {
            logger.warning("Failed to fetch validators: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func fetchInflation() async -> Double? {
        do {
            return try await stakingService.fetchInflationRate()
        } catch {
            logger.warning("Failed to fetch inflation: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func fetchRentReserve() async -> UInt64 {
        do {
            return try await stakingService.fetchRentReserve()
        } catch {
            logger.warning("Failed to fetch rent reserve: \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }
}

/// A single stake-account row in the Solana DeFi stake segment. One row per
/// stake account — a wallet can hold N. `validatorName` / `validatorLogoURL`
/// fall back to a truncated vote pubkey when the validator set / metadata
/// couldn't be enriched; `apyPercent` is nil when no source produced a positive
/// value (the view hides the APY row). Carries the full `SolanaStakeAccount` so
/// the row actions can hand it straight to the `FunctionTransactionType.solana*`
/// flows without re-querying.
struct SolanaStakeAccountRow: Identifiable, Equatable, Sendable {
    var id: String { stakeAccount.pubkey }
    let stakeAccount: SolanaStakeAccount
    let validatorName: String
    let validatorVotePubkey: String?
    let validatorLogoURL: URL?
    /// Delegated SOL (human-decimal), 0 for an initialized-but-undelegated
    /// account.
    let delegatedAmount: Decimal
    /// Rent-exempt reserve held by the account (human-decimal SOL) — not part of
    /// the delegated stake; shown so the user understands the account's lamports.
    let rentReserve: Decimal
    let activationState: SolanaStakeActivationState
    /// Fractional APY (`0.067` = 6.7%), or `nil` to hide the row.
    let apyPercent: Decimal?

    /// Whether a move-stake can be started from this account — only a fully
    /// active delegation; an activating/deactivating/inactive account has no
    /// stable stake to move.
    var canMoveStake: Bool { activationState == .active }

    /// Whether the account can be unstaked (deactivated) — only an active or
    /// activating delegation; a deactivating/inactive one has nothing to cool
    /// down.
    var canUnstake: Bool { activationState == .active || activationState == .activating }

    /// Whether the cooled-down lamports can be withdrawn — only once fully
    /// inactive.
    var canWithdraw: Bool { activationState == .inactive }
}
