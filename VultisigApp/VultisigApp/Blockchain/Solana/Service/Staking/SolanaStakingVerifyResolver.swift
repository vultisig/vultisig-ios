//
//  SolanaStakingVerifyResolver.swift
//  VultisigApp
//
//  Shared Verify → KeysignPayload bridge for Solana native staking. Dispatches
//  a `SolanaStakingPayload` to the right `SolanaStakingSignDataResolver` branch
//  and fetches the per-op live inputs (delegate needs rent reserve + validator
//  set; deactivate/withdraw operate on an existing account and need neither).
//
//  Lives once here so both entry points — `SendCryptoVerifyLogic` and
//  `FunctionCallVerifyViewModel` — share identical resolution rather than each
//  re-implementing the op switch.
//

import Foundation

enum SolanaStakingVerifyResolver {

    /// Resolves the relayed `SignSolana` for a staking op. `basePayload` must
    /// already carry the `solanaStakingPayload` (via `withSolanaStakingPayload`).
    static func resolve(
        payload: SolanaStakingPayload,
        basePayload: KeysignPayload,
        coin: Coin,
        stakingService: SolanaStakingServiceProtocol = SolanaStakingService.shared
    ) async throws -> SignSolana {
        switch payload.opType {
        case .delegate:
            let rentReserve = try await stakingService.fetchRentReserve()
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
            return try SolanaStakingSignDataResolver.resolveWithdraw(basePayload: basePayload)
        case .moveStakeStep:
            // The re-delegate sub-step delegates to validator B, so it needs the
            // known-vote set for the preflight; deactivate ignores it.
            let knownVotePubkeys = Set(
                ((try? await stakingService.fetchValidators()) ?? []).map(\.votePubkey)
            )
            return try SolanaStakingSignDataResolver.resolveMoveStake(
                basePayload: basePayload,
                knownVotePubkeys: knownVotePubkeys
            )
        }
    }
}
