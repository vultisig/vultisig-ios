//
//  SolanaStakingVerifyResolver.swift
//  VultisigApp
//
//  Shared Verify → KeysignPayload bridge for Solana native staking. Dispatches
//  a `SolanaStakingPayload` to the right `SolanaStakingSignDataResolver` branch
//  and fetches the per-op live inputs (delegate needs rent reserve + validator
//  set; withdraw re-checks its exact account balance and simulates the unsigned
//  transaction; deactivate needs neither).
//
//  Lives once here so both entry points — `SendCryptoVerifyLogic` and
//  `FunctionCallVerifyViewModel` — share identical resolution rather than each
//  re-implementing the op switch.
//

import Foundation

protocol SolanaWithdrawPreflightChecking {
    func validateSolanaWithdraw(encodedTransaction: String) async throws
}

extension SolanaService: SolanaWithdrawPreflightChecking {}

enum SolanaStakingVerifyResolver {

    /// Resolves the relayed `SignSolana` for a staking op. `basePayload` must
    /// already carry the `solanaStakingPayload` (via `withSolanaStakingPayload`).
    static func resolve(
        payload: SolanaStakingPayload,
        basePayload: KeysignPayload,
        coin: Coin,
        stakingService: SolanaStakingServiceProtocol = SolanaStakingService.shared,
        withdrawPreflight: SolanaWithdrawPreflightChecking = SolanaService.shared
    ) async throws -> SignSolana {
        switch payload.opType {
        case .delegate:
            // Rent reserve is informational on this verify branch — the funding
            // amount already bakes it in upstream — so a transient rent-exemption
            // outage must not block an otherwise-valid delegate. Fall back to 0
            // rather than hard-fail. The validator set, by contrast, stays a soft
            // dependency (graceful preflight degradation; see SolanaValidatorPreflight).
            let rentReserve = (try? await stakingService.fetchRentReserve()) ?? 0
            let knownVotePubkeys = Set(
                ((try? await stakingService.fetchValidators()) ?? []).map(\.votePubkey)
            )
            let balance = UInt64(coin.rawBalance) ?? 0
            return try SolanaStakingSignDataResolver.resolve(
                basePayload: basePayload,
                rentReserve: rentReserve,
                knownVotePubkeys: knownVotePubkeys,
                balance: balance
            )
        case .unstake:
            return try SolanaStakingSignDataResolver.resolveDeactivate(basePayload: basePayload)
        case .withdraw:
            guard let stakeAccountAddress = payload.stakeAccount else {
                throw SolanaStakingSignDataResolver.Errors.missingPayloadField("stakeAccount")
            }
            guard let liveAccount = try await stakingService.fetchStakeAccount(address: stakeAccountAddress),
                  liveAccount.lamports == payload.lamports else {
                throw SolanaWithdrawPreflightError.stakeNotReady
            }
            let signSolana = try SolanaStakingSignDataResolver.resolveWithdraw(basePayload: basePayload)
            guard let rawTransaction = signSolana.rawTransactions.first else {
                throw SolanaStakingSignDataResolver.Errors.missingPayloadField("rawTransaction")
            }
            try await withdrawPreflight.validateSolanaWithdraw(encodedTransaction: rawTransaction)
            return signSolana
        }
    }
}
