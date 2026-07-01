//
//  SolanaStakingAPYResolver.swift
//  VultisigApp
//
//  Resolves a per-validator staking APY for the Solana DeFi stake rows. Two
//  sources, in order:
//
//    1. Stakewiz `apy_estimate` passthrough — the metadata provider already
//       fetches `/validators` and caches it 1 h; the estimate it carries
//       (`ValidatorMetadata.apyEstimate`, stored as a fraction) is the
//       preferred, network-measured value.
//    2. On-chain fallback — derive APR from the network inflation rate and the
//       fraction of supply staked, net of the validator's commission, then
//       compound it over the epochs-per-year to an APY:
//         APR = (inflation / fractionStaked) × (1 − commission)
//         APY = (1 + APR / N)^N − 1   (N = epochs per year)
//
//  When neither source yields a positive value the resolver returns `nil` and
//  the view hides the APY row. Analog: `CosmosStakingAPYResolver`.
//
//  Inflation is cached 10 min by `SolanaStakingService`; the fraction-staked
//  inputs (validator activated stake totals) come from the already-fetched
//  validator set, so the fallback adds no extra RPC beyond what the row refresh
//  already does.
//

import Foundation

protocol SolanaStakingAPYResolverProtocol: Sendable {
    /// Resolves the APY fraction (e.g. `0.067` for 6.7%) for `validator`.
    /// `metadataAPY` is the Stakewiz passthrough when present; `inflationRate`
    /// and `totalActivatedStake` drive the on-chain fallback. Returns `nil` when
    /// no source produces a positive APY.
    func apy(
        for validator: SolanaValidator,
        metadataAPY: Decimal?,
        inflationRate: Double?,
        totalActivatedStake: UInt64,
        totalSupplyLamports: UInt64?
    ) -> Decimal?
}

struct SolanaStakingAPYResolver: SolanaStakingAPYResolverProtocol {

    /// Mainnet epoch is ~2 days, so ~182 epochs per year. Used to compound the
    /// per-epoch APR into an APY in the on-chain fallback.
    static let epochsPerYear: Decimal = 182

    func apy(
        for validator: SolanaValidator,
        metadataAPY: Decimal?,
        inflationRate: Double?,
        totalActivatedStake: UInt64,
        totalSupplyLamports: UInt64?
    ) -> Decimal? {
        // 1. Stakewiz passthrough — already a fraction, already commission-net.
        if let metadataAPY, metadataAPY > 0 {
            return metadataAPY
        }
        // 2. On-chain fallback.
        return Self.onChainAPY(
            inflationRate: inflationRate,
            commission: validator.commission,
            totalActivatedStake: totalActivatedStake,
            totalSupplyLamports: totalSupplyLamports
        )
    }

    /// `APY = (1 + APR/N)^N − 1` where
    /// `APR = (inflation / fractionStaked) × (1 − commission)`. Returns `nil`
    /// when any input is missing or collapses the result to zero.
    static func onChainAPY(
        inflationRate: Double?,
        commission: Int,
        totalActivatedStake: UInt64,
        totalSupplyLamports: UInt64?
    ) -> Decimal? {
        guard
            let inflationRate, inflationRate > 0,
            let totalSupplyLamports, totalSupplyLamports > 0,
            totalActivatedStake > 0
        else { return nil }

        let inflation = Decimal(inflationRate)
        let fractionStaked = Decimal(totalActivatedStake) / Decimal(totalSupplyLamports)
        guard fractionStaked > 0 else { return nil }

        let commissionFraction = clamp01(Decimal(commission) / 100)
        let apr = (inflation / fractionStaked) * (1 - commissionFraction)
        guard apr > 0 else { return nil }

        let epochs = epochsPerYear
        let perEpoch = apr / epochs
        // (1 + perEpoch)^N − 1, via Double pow — fractional exponents aren't
        // available on Decimal and APY display only needs 2-dp precision.
        let base = (1 as Decimal) + perEpoch
        let apyDouble = pow((base as NSDecimalNumber).doubleValue, (epochs as NSDecimalNumber).doubleValue) - 1
        guard apyDouble.isFinite, apyDouble > 0 else { return nil }
        return Decimal(apyDouble)
    }

    private static func clamp01(_ value: Decimal) -> Decimal {
        if value < 0 { return 0 }
        if value > 1 { return 1 }
        return value
    }
}
