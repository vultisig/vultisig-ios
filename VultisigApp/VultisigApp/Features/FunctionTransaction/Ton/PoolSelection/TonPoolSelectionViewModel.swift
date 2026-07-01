//
//  TonPoolSelectionViewModel.swift
//  VultisigApp
//
//  Backs the TON staking-pool picker sheet. Loads the pool list from
//  `TonService`, keeps verified pools with capacity sorted by APY descending,
//  and surfaces search + selection state. Cache is per-sheet (no SwiftData),
//  mirroring `StakingValidatorPickerViewModel`.
//

import Foundation
import OSLog

@MainActor
final class TonPoolSelectionViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published private(set) var pools: [TonStakingPool] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: String?

    private let decimals: Int
    private let service: TonService
    private let logger = Logger(
        subsystem: "com.vultisig.app",
        category: "ton-pool-selection"
    )

    init(decimals: Int, service: TonService = .shared) {
        self.decimals = decimals
        self.service = service
    }

    var filteredPools: [TonStakingPool] {
        guard searchText.isNotEmpty else { return pools }
        let needle = searchText.lowercased()
        return pools.filter { pool in
            pool.name.lowercased().contains(needle)
                || pool.address.lowercased().contains(needle)
        }
    }

    func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let raw = try await service.getStakingPools()
            pools = Self.sortAndFilter(raw, decimals: decimals)
        } catch {
            logger.error("TON staking pools fetch failed: \(error.localizedDescription, privacy: .public)")
            self.error = error.localizedDescription
        }
    }

    /// Keeps verified **nominator** pools that still have capacity, sorted by
    /// APY descending. Liquid-staking pools (e.g. Tonstakers / `liquidTF`) are
    /// excluded because our `"d"`/`"w"` deposit mechanism can't stake into them.
    /// Surfaced as a static helper so tests can pin the sort/filter contract
    /// independent of the network layer.
    static func sortAndFilter(_ raw: [TonStakingPoolListEntry], decimals: Int) -> [TonStakingPool] {
        raw
            .filter { $0.verified }
            .map { TonStakingPool(entry: $0, decimals: decimals) }
            .filter { $0.isNominatorPool }
            .filter { $0.hasCapacity }
            .sorted { $0.apy > $1.apy }
    }
}
