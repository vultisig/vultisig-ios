//
//  OnboardingDevicesSelectionScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/01/2026.
//

import SwiftUI
import RiveRuntime

struct OnboardingDevicesSelectionScreen: View {
    let tssType: TssType
    let keyImportInput: KeyImportInput?

    @State private var selectedDeviceCount: Int = 0
    @State private var animationVM: RiveViewModel? = nil

    @Environment(\.router) var router

    var body: some View {
        Screen {
            VStack(spacing: 0) {
                animationVM?.view()
                    .frame(maxWidth: 400)
                Spacer()

                VStack(spacing: 16) {
                    tipView
                    PrimaryButton(title: "getStarted".localized, action: onContinue)
                }
            }
            .padding(.top, 64)
        }
        .screenIgnoresTopEdge()
        .screenBackground(.clear)
        .background(background)
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
                #if os(iOS)
                HapticFeedbackManager.shared.startHapticFeedback(duration: 0.1)
                #endif
            }
        }
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

    var background: some View {
        DevicesSelectionBackground()
    }
}

#Preview {
    OnboardingDevicesSelectionScreen(
        tssType: .Keygen,
        keyImportInput: nil
    )
}
