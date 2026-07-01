//
//  StakingValidatorConvertible.swift
//  VultisigApp
//
//  Bridges the per-chain on-chain validator types to the shared picker. A
//  conforming type keeps its full chain shape (used for selection + signing) and
//  exposes a `StakingValidator` display projection plus the search terms the
//  picker filters on. The sort/filter contract for each chain's bonded set lives
//  here too, so the picker stays chain-agnostic and tests can pin it directly.
//

import Foundation

/// A chain validator the shared picker can render + select. `id` is the
/// selection identity (Cosmos operator address / Solana vote pubkey).
protocol StakingValidatorConvertible: Identifiable where ID == String {
    /// Lowercased-matched search fields (moniker/name + address).
    var searchTerms: [String] { get }
    /// Display projection rendered by `StakingValidatorCard`, using the chain's
    /// ticker + decimals to scale the power/stake subline.
    func makeStakingValidator(ticker: String, decimals: Int) -> StakingValidator
}

// MARK: - Cosmos

extension CosmosValidator: Identifiable {
    var id: String { operatorAddress }
}

extension CosmosValidator: StakingValidatorConvertible {
    var searchTerms: [String] { [moniker, operatorAddress] }

    func makeStakingValidator(ticker: String, decimals: Int) -> StakingValidator {
        let display = moniker.isEmpty ? Self.truncatedAddress(operatorAddress) : moniker
        let monogramSource = moniker.isEmpty ? operatorAddress : moniker
        let monogram = String(monogramSource.prefix(1)).uppercased()
        return StakingValidator(
            name: display,
            subtitle: "\(Self.formatVotingPower(votingPower, decimals: decimals)) \(ticker)",
            commission: Self.formatCommission(commission),
            avatar: .keybase(identity: identity, monogram: monogram)
        )
    }

    /// Keeps bonded + un-jailed validators, sorted by descending voting power.
    static func sortAndFilter(_ raw: [CosmosValidator]) -> [CosmosValidator] {
        raw
            .filter { !$0.jailed && $0.status == .bonded }
            .sorted { $0.votingPower > $1.votingPower }
    }

    /// Compact `terravaloper1abc…xyz` truncation for fallback display.
    static func truncatedAddress(_ address: String) -> String {
        guard address.count > 14 else { return address }
        return address.prefix(8) + "…" + address.suffix(4)
    }

    /// Voting power arrives as base-units `Decimal` (e.g. uluna for Terra, the
    /// 8-decimal base unit for QBTC). Scale down by the chain's native decimals
    /// and round to whole tokens so values like "200,392 LUNA" match Figma.
    static func formatVotingPower(_ value: Decimal, decimals: Int) -> String {
        let divisor = pow(Decimal(10), decimals)
        let scaled = value / divisor
        let nsNumber = NSDecimalNumber(decimal: scaled)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: nsNumber) ?? "0"
    }

    static func formatCommission(_ commission: Decimal) -> String {
        let percentage = commission * 100
        let nsNumber = NSDecimalNumber(decimal: percentage)
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return "\(formatter.string(from: nsNumber) ?? "0")%"
    }
}

// MARK: - Solana

extension SolanaValidator: StakingValidatorConvertible {
    // `id` (= votePubkey) + `Identifiable` already declared on the model.
    var searchTerms: [String] { [displayName, votePubkey] }

    func makeStakingValidator(ticker: String, decimals: Int) -> StakingValidator {
        let monogram = String(displayName.prefix(1)).uppercased()
        return StakingValidator(
            name: displayName,
            subtitle: "\(Self.formatStake(activatedStake, decimals: decimals)) \(ticker)",
            commission: "\(commission)%",
            avatar: .logo(url: logoURL, monogram: monogram)
        )
    }

    /// Keeps non-delinquent validators that voted in the current epoch, sorted by
    /// descending activated stake.
    static func sortAndFilter(_ raw: [SolanaValidator]) -> [SolanaValidator] {
        raw
            .filter { !$0.isDelinquent && $0.epochVoteAccount }
            .sorted { $0.activatedStake > $1.activatedStake }
    }

    /// Activated stake arrives in lamports; scale down by the chain's native
    /// decimals and round to whole tokens for the subline.
    static func formatStake(_ value: UInt64, decimals: Int) -> String {
        let divisor = pow(Decimal(10), decimals)
        let scaled = Decimal(value) / divisor
        let nsNumber = NSDecimalNumber(decimal: scaled)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: nsNumber) ?? "0"
    }
}
