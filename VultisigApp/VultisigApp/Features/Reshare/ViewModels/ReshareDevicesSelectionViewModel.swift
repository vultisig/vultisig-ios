//
//  ReshareDevicesSelectionViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 06/07/2026.
//

import Foundation

/// Drives the reshare "How many devices do you have?" step: tracks the
/// Rive stepper selection, gates counts below the vault's required number
/// of active signers, and resolves the destination for the chosen setup.
final class ReshareDevicesSelectionViewModel: ObservableObject {

    enum Destination: Equatable {
        case fastVaultPassword(isExistingVault: Bool)
        case peerDiscovery(setupType: KeyImportSetupType)
    }

    /// Zero-based stepper position reported by the Rive animation
    /// (0 → "1" device, 1 → "2", 2 → "3", 3 → "4+").
    @Published var selectedIndex: Int = 0
    @Published var isFastVaultEligible = false
    @Published var isLoading = false

    /// Devices currently registered on the vault (including a FastVault
    /// server signer, when present).
    let currentDeviceCount: Int

    /// Minimum number of devices the new setup must keep so the vault's
    /// signing threshold stays reachable.
    let requiredActiveSigners: Int

    private let fastVaultService: FastVaultService

    init(
        currentDeviceCount: Int,
        requiredActiveSigners: Int,
        fastVaultService: FastVaultService = .shared
    ) {
        self.currentDeviceCount = currentDeviceCount
        self.requiredActiveSigners = requiredActiveSigners
        self.fastVaultService = fastVaultService
    }

    var selectedDeviceCount: Int {
        selectedIndex + 1
    }

    var isThresholdMet: Bool {
        selectedDeviceCount >= requiredActiveSigners
    }

    var destination: Destination {
        guard selectedIndex > 0 else {
            return .fastVaultPassword(isExistingVault: isFastVaultEligible)
        }
        return .peerDiscovery(setupType: .secure(numberOfDevices: selectedDeviceCount))
    }

    var thresholdWarningText: String {
        String(
            format: "thresholdNotMetDescription".localized,
            currentDeviceCount,
            selectedDeviceCount,
            requiredActiveSigners
        )
    }

    @MainActor func load(vault: Vault) async {
        isLoading = true
        isFastVaultEligible = await fastVaultService.isEligibleForFastSign(vault: vault)
        isLoading = false
    }
}
