//
//  CosmosStakingValidatorRows.swift
//  VultisigApp
//

import Foundation

/// The validator rows of a Cosmos staking operation: one for a delegation or
/// undelegation, source then destination for a redelegation, and the one or
/// many validators a reward claim reads from.
enum CosmosStakingValidatorRows {
    struct Row: Equatable {
        /// Localization key of the label.
        let labelKey: String
        let value: String
    }

    /// Falls back to a truncated valoper for any validator not in
    /// `validators`, so a row is never blank while the list is loading.
    static func rows(for payload: CosmosStakingPayload, validators: [String: CosmosValidator]) -> [Row] {
        switch payload.opType {
        case .delegate, .undelegate:
            return payload.validatorAddress.map { [Row(labelKey: "validator", value: resolve($0, in: validators))] } ?? []
        case .redelegate:
            var rows: [Row] = []
            if let source = payload.validatorSrcAddress {
                rows.append(Row(labelKey: "sourceValidator", value: resolve(source, in: validators)))
            }
            if let destination = payload.validatorDstAddress {
                rows.append(Row(labelKey: "destinationValidator", value: resolve(destination, in: validators)))
            }
            return rows
        case .withdrawRewards:
            guard let addresses = payload.validators, !addresses.isEmpty else { return [] }
            let label = addresses.count == 1
                ? resolve(addresses[0], in: validators)
                : String(format: "claimFromValidators".localized, addresses.count)
            return [Row(labelKey: "validator", value: label)]
        }
    }

    static func resolve(_ valoper: String, in validators: [String: CosmosValidator]) -> String {
        guard let validator = validators[valoper] else {
            return truncated(valoper)
        }
        let display = validator.moniker.isEmpty ? truncated(valoper) : validator.moniker
        let percent = (validator.commission * 100).formatted(.number.precision(.fractionLength(0...2)))
        return "\(display) (\(percent)% \("commission".localized))"
    }

    private static func truncated(_ value: String) -> String {
        guard value.count > 14 else { return value }
        return value.prefix(8) + "…" + value.suffix(4)
    }
}
