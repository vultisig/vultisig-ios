//
//  KeyImportDeviceCountScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/01/2026.
//

import SwiftUI
import RiveRuntime

struct KeyImportDeviceCountScreen: View {
    let mnemonic: String
    let chainSettings: [ChainImportSetting]

    @State private var selectedDeviceCount: Int = 0
    @State private var animationVM: RiveViewModel? = nil

    @Environment(\.router) var router

    var body: some View {
        Screen {
            VStack(spacing: 16) {
                animationVM?.view()
                tipView
                PrimaryButton(title: "next".localized, action: onContinue)
            }
            .padding(.top, 32)
        }
        .background(VaultMainScreenBackground())
        .onLoad(perform: onLoad)
    }

    var tipView: some View {
        HStack(spacing: 8) {
            Icon(named: "lightbulb", size: 12)
            Text("seedPhraseImportTip".localized)
                .foregroundStyle(Theme.colors.textPrimary)
                .font(Theme.fonts.caption12)
        }
    }

    private func onLoad() {
        animationVM = RiveViewModel(fileName: "devices_component")
        animationVM?.fit = .layout

        animationVM?.riveModel?.enableAutoBind { instance in
            instance.numberProperty(fromPath: "Index")?.addListener { value in
                selectedDeviceCount = Int(value)
            }
        }
    }

    private func onContinue() {
        router.navigate(to: OnboardingRoute.vaultSetup(
            tssType: .KeyImport,
            keyImportInput: KeyImportInput(
                mnemonic: mnemonic,
                chainSettings: chainSettings
            ),
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
    KeyImportDeviceCountScreen(
        mnemonic: "test mnemonic",
        chainSettings: [ChainImportSetting(chain: .bitcoin)]
    )
}
