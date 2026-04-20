//
//  VaultDefiChainsService.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/10/2025.
//

import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.vultisig.app", category: "vault-defi-chains-service")

// Enables Defi chains for the first time for vaults that were created before Defi features where released
// TODO: - To be removed after release
struct VaultDefiChainsService {
    @AppStorage("enabled_vaults_4") private var enabledVaults: [String] = []

    @MainActor
    func enableDefiChainsIfNeeded(for vault: Vault) async {
        guard !enabledVaults.contains(vault.pubKeyECDSA) else {
            return
        }

        let allDefiChains = (vault.chains + vault.defiChains).filter { CoinAction.defiChains.contains($0) }
        vault.defiChains = Array(Set(allDefiChains))
        vault.defiPositions = vault.defiPositions.map {
            if $0.chain == .thorChain {
                return DefiPositions(
                    chain: .thorChain,
                    bonds: $0.bonds,
                    staking: $0.staking.filter { $0.ticker.lowercased() != "stcy" },
                    lps: $0.lps
                )
            } else {
                return $0
            }
        }
        vault.stakePositions = []
        do {
            try await Storage.shared.save()
            enabledVaults.append(vault.pubKeyECDSA)
        } catch {
            logger.error("Failed to save DeFi chains for vault: \(error)")
        }
    }
}
