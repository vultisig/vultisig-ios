//
//  OnboardingDevicesSelectionScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/01/2026.
//

import SwiftUI

struct OnboardingDevicesSelectionScreen: View {
    let tssType: TssType
    let keyImportInput: KeyImportInput?

    @State private var selectedDeviceCount: Int = 0

    @Environment(\.router) var router

    var body: some View {
        DevicesSelectionView(
            selectedIndex: $selectedDeviceCount,
            tipText: "seedPhraseImportTip".localized,
            buttonTitle: "getStarted".localized,
            onContinue: onContinue
        )
    }

    private func onContinue() {
        router.navigate(to: OnboardingRoute.vaultSetupInformation(
            tssType: tssType,
            keyImportInput: keyImportInput,
            setupType: setupType
        ))
    }

    var setupType: KeyImportSetupType {
        guard selectedDeviceCount > 0 else {
            return .fast
        }

        return .secure(numberOfDevices: selectedDeviceCount + 1)
    }
}

#Preview {
    OnboardingDevicesSelectionScreen(
        tssType: .Keygen,
        keyImportInput: nil
    )
}
