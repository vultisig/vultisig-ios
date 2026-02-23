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
        GeometryReader { proxy in
            let width = min(proxy.size.height, proxy.size.width)
            ZStack(alignment: .top) {
                Theme.colors.bgPrimary
                    .ignoresSafeArea(.all)
                linearGradient
                    .frame(width: proxy.size.width, height: 100)
                    .ignoresSafeArea(edges: .top)
                    .offset(y: -24)
                let radialGradientWidth = min(width, 300)
                radialGradient
                    .frame(width: radialGradientWidth, height: radialGradientWidth * 1.5)
                    .offset(y: -radialGradientWidth / 1.3)
            }
            .ignoresSafeArea()
        }
    }

    var radialGradient: some View {
        EllipticalGradient(
            stops: [
                Gradient.Stop(color: Color(hex: "084BFF"), location: 0.00),
                Gradient.Stop(color: Color(red: 0.01, green: 0.07, blue: 0.17).opacity(0), location: 1.00)
            ],
            center: UnitPoint(x: 0.5, y: 0.5)
        )
        .blur(radius: 36)
    }

    var linearGradient: some View {
        LinearGradient(
            stops: [
                Gradient.Stop(color: Color(red: 0.01, green: 0.07, blue: 0.17).opacity(0), location: 0.00),
                Gradient.Stop(color: Color(red: 0.02, green: 0.22, blue: 0.78), location: 1.00)
            ],
            startPoint: UnitPoint(x: 0.5, y: 0),
            endPoint: UnitPoint(x: 0.5, y: 1)
        )
        .blur(radius: 48)
    }
}

#Preview {
    OnboardingDevicesSelectionScreen(
        tssType: .Keygen,
        keyImportInput: nil
    )
}
