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

    var warningLocalizationKey: String? {
        switch self {
        case .checking, .available:
            nil
        case .halted:
            "mayaCacaoStakingHaltedWarning"
        case .unavailable:
            "mayaCacaoStakingUnavailableWarning"
        }
    }
}

protocol StakeInteractor {
    /// Returns one DTO per coin that was successfully fetched. Per-coin failures are silently
    /// omitted — storage upserts only what's returned, so the persisted row keeps its last good
    /// value until the next refresh.
    func fetchStakePositions(vault: Vault) async -> [StakePositionData]
    func fetchActionAvailability() async -> StakeActionAvailability
}

extension StakeInteractor {
    // swiftlint:disable:next async_without_await
    func fetchActionAvailability() async -> StakeActionAvailability {
        .available
    }
}
