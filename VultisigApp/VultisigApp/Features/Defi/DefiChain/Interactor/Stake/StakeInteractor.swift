//
//  StakeInteractor.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/11/2025.
//

enum StakeActionAvailability: Equatable, Sendable {
    case checking
    case available
    case halted
    case unavailable

    var disablesActions: Bool {
        self != .available
    }
}

typealias StakeActionAvailabilities = [CoinMeta: StakeActionAvailability]

protocol StakeInteractor {
    /// Returns one DTO per coin that was successfully fetched. Per-coin failures are silently
    /// omitted — storage upserts only what's returned, so the persisted row keeps its last good
    /// value until the next refresh.
    func fetchStakePositions(vault: Vault) async -> [StakePositionData]
    /// Returns availability overrides keyed by the concrete position coin. Missing coins use the
    /// presentation default (`available`), which lets mixed chains gate contract positions without
    /// disabling unrelated native-module actions.
    func fetchActionAvailabilities(for coins: [CoinMeta]) async -> StakeActionAvailabilities
}

extension StakeInteractor {
    // swiftlint:disable:next async_without_await
    func fetchActionAvailabilities(for coins: [CoinMeta]) async -> StakeActionAvailabilities {
        coins.reduce(into: [:]) { result, coin in
            result[coin] = .available
        }
    }
}
