//
//  KeyImportNewVaultSetupScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 11/12/2025.
//

import SwiftUI
import RiveRuntime

struct KeyImportNewVaultSetupScreen: View {
    let vault: Vault
    let keyImportInput: KeyImportInput?
    let fastSignConfig: FastSignConfig?
    let setupType: KeyImportSetupType

    @State private var animationVM: RiveViewModel? = nil
    @State private var showAnimation = false
    @State private var showContent = false

    @Environment(\.router) var router

    var selectedTab: SetupVaultState {
        setupType == .fast ? .fast : .secure
    }

    var deviceCountText: String {
        switch setupType {
        case .fast:
            return "oneDevicePlusServer".localized
        case .secure(let count):
            return String(format: "nDevicesSetup".localized, count)
        }
    }

    var deviceCountSubtitle: String {
        switch setupType {
        case .fast:
            return "oneDevicePlusServerSubtitle".localized
        case .secure(let count):
            return String(format: "nDevicesSetupSubtitle".localized, count)
        }
    }
    
    var body: some View {
        Screen(edgeInsets: .init(leading: 0, trailing: 0)) {
            VStack(spacing: 0) {
                Spacer()

                animation
                    .opacity(showAnimation ? 1 : 0)
                    .blur(radius: showAnimation ? 0 : 10)
                    .animation(.easeInOut, value: showAnimation)

                Spacer()

                VStack(spacing: 0) {
                    informationView
                        .opacity(showContent ? 1 : 0)
                        .offset(y: showContent ? 0 : 20)
                        .blur(radius: showContent ? 0 : 10)
                        .animation(.spring, value: showContent)

                    Spacer().frame(maxHeight: 64)

                    PrimaryButton(title: "setup") {
                        router.navigate(to: KeygenRoute.peerDiscovery(
                            tssType: .KeyImport,
                            vault: vault,
                            selectedTab: selectedTab,
                            fastSignConfig: fastSignConfig,
                            keyImportInput: keyImportInput
                        ))
                    }
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 20)
                    .blur(radius: showContent ? 0 : 10)
                    .animation(.spring.delay(0.1), value: showContent)
                }
                .padding(.horizontal, 16)
            }
        }
        .onLoad {
            setData()
        }
        .onDisappear {
            animationVM?.reset()
        }
    }

    var animation: some View {
        Group {
            if let animationVM = animationVM {
                animationVM.view()
                    .frame(height: 300)
            }
        }
    }
    
    var informationView: some View {
        VStack(alignment: .leading, spacing: 24) {
            CustomHighlightText(
                "yourNewVaultSetup".localized,
                highlight: "yourNewVaultSetupHighlight".localized,
                style: LinearGradient.primaryGradientHorizontal
            )
            .foregroundStyle(Theme.colors.textPrimary)
            .font(Theme.fonts.title2)
            
            OnboardingInformationRowView(
                title: deviceCountText,
                subtitle: deviceCountSubtitle,
                icon: "devices"
            )
            
            OnboardingInformationRowView(
                title: "whySecureServer".localized,
                subtitle: "whySecureServerSubtitle".localized,
                icon: "secure"
            )
            
            appStoreReadyView
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    
    var appStoreReadyView: some View {
        HStack(alignment: .top, spacing: 12) {
            Icon(named: "shield-check", color: Theme.colors.alertInfo, size: 20)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("appStoreReady".localized)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .font(Theme.fonts.subtitle)
                
                Text("appStoreReadyDescription".localized)
                    .foregroundStyle(Theme.colors.textSecondary)
                    .font(Theme.fonts.footnote)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .inset(by: 0.5)
                .fill(
                    LinearGradient(
                        stops: [
                            Gradient.Stop(color: Color(red: 0.04, green: 0.07, blue: 0.18), location: 0.00),
                            Gradient.Stop(color: Color(red: 0.22, green: 0.39, blue: 0.6).opacity(0), location: 1.00),
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .strokeBorder(Color(hex: "5CA7FF").opacity(0.3), style: .init(lineWidth: 1, dash: [4, 4]))
        )
        .background(Color(hex: "376499").opacity(0.3).clipShape(RoundedRectangle(cornerRadius: 12)))
    }

    private func setData() {
        if animationVM == nil {
            animationVM = RiveViewModel(fileName: setupType.vaultSetupAnimationName)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            showAnimation = true
            showContent = true
        }
    }
}

#Preview {
    KeyImportNewVaultSetupScreen(
        vault: .example,
        keyImportInput: .init(
            mnemonic: "",
            chainSettings: []
        ),
        fastSignConfig: .init(
            email: "",
            password: "",
            hint: nil,
            isExist: false
        ),
        setupType: .secure(numberOfDevices: 2)
    )
}
