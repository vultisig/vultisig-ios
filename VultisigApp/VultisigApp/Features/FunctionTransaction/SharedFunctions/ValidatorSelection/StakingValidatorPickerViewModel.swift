//
//  StakingValidatorPickerViewModel.swift
//  VultisigApp
//
//  Backs the shared validator-picker sheet for any chain. Loads the chain's
//  validator set through the injected `StakingValidatorSource`, then surfaces
//  search + load state. Replaces the per-chain Cosmos/Solana picker view-models.
//
//  Cache is per-sheet (no SwiftData persistence); the source's own service layer
//  owns any process-wide caching.
//

import Foundation
import OSLog

@MainActor
final class StakingValidatorPickerViewModel<V: StakingValidatorConvertible>: ObservableObject {
    @Published var searchText: String = ""
    @Published private(set) var validators: [V] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: String?

    private let source: StakingValidatorSource<V>
    private let logger = Logger(
        subsystem: "com.vultisig.app",
        category: "staking-validator-picker"
    )

    init(source: StakingValidatorSource<V>) {
        self.source = source
    }

    var filteredValidators: [V] {
        guard searchText.isNotEmpty else { return validators }
        let needle = searchText.lowercased()
        return validators.filter { validator in
            validator.searchTerms.contains { $0.lowercased().contains(needle) }
        }
    }

    func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            validators = try await source.load()
        } catch {
            logger.error("Validator fetch failed: \(error.localizedDescription, privacy: .public)")
            // Keep the raw error in the log; surface the source's user-facing
            // message (raw description for Cosmos, a stable localized string for
            // Solana) rather than backend/system English.
            self.error = source.userFacingError(error)
        }
    }
}
