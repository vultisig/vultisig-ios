//
//  ValidatorSelectionViewModel.swift
//  VultisigApp
//
//  Backs the cosmos validator-picker sheet. Loads the bonded validator set
//  from `CosmosStakingService`, sorts by voting power descending, filters
//  jailed validators out, and surfaces search + selection state.
//
//  Cache is per-sheet (the spec D-5 calls for no SwiftData persistence).
//

import Foundation
import OSLog

@MainActor
final class ValidatorSelectionViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published private(set) var validators: [CosmosValidator] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: String?

    let chain: Chain
    private let service: CosmosStakingServiceProtocol
    private let logger = Logger(
        subsystem: "com.vultisig.app",
        category: "validator-selection"
    )

    /// Validators excluded from the visible list — e.g. the source validator
    /// when redelegating (you can't redelegate to yourself). Defaults to
    /// empty for the delegate flow.
    let excludedValidators: Set<String>

    init(
        chain: Chain,
        service: CosmosStakingServiceProtocol = CosmosStakingService(),
        excludedValidators: Set<String> = []
    ) {
        self.chain = chain
        self.service = service
        self.excludedValidators = excludedValidators
    }

    var filteredValidators: [CosmosValidator] {
        let pool = validators.filter { !excludedValidators.contains($0.operatorAddress) }
        guard searchText.isNotEmpty else { return pool }
        let needle = searchText.lowercased()
        return pool.filter { validator in
            validator.moniker.lowercased().contains(needle)
                || validator.operatorAddress.lowercased().contains(needle)
        }
    }

    func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let raw = try await service.fetchValidators(chain: chain)
            validators = Self.sortAndFilter(raw)
        } catch {
            logger.error("Validator fetch failed: \(error.localizedDescription, privacy: .public)")
            self.error = error.localizedDescription
        }
    }

    /// Keeps bonded + un-jailed validators, sorted by descending voting power.
    /// Surfaced as a static helper so tests can pin the sort/filter contract
    /// independent of the network layer.
    static func sortAndFilter(_ raw: [CosmosValidator]) -> [CosmosValidator] {
        raw
            .filter { !$0.jailed && $0.status == .bonded }
            .sorted { $0.votingPower > $1.votingPower }
    }
}
