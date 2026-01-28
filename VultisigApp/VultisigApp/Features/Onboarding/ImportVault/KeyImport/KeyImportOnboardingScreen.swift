//
//  KeyImportOnboardingScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 09/12/2025.
//

import SwiftUI
import RiveRuntime

struct KeyImportOnboardingScreen: View {
    @State var animationVM: RiveViewModel?
    @State var showInformation: Bool = false
    @State var informationOpacity: CGFloat = 0
    @Environment(\.router) var router

    var body: some View {
        Screen {
            VStack(spacing: .zero) {
                animationVM?.view()
                    .frame(maxHeight: 270)
                    .scaledToFit()
                    .offset(y: showInformation ? 0 : -24)
                Group {
                    Spacer()
                    Group {
                        informationView
                        Spacer().frame(maxHeight: 65)
                        PrimaryButton(title: "getStarted") {
                            router.navigate(
                                to: OnboardingRoute.importSeedphrase(
                                    keyImportInput: nil
                                )
                            )
                        }
                    }
                    .opacity(informationOpacity)
                }
                .showIf(showInformation)
            }
            .frame(maxHeight: .infinity)
        }
        .onAppear {
            animationVM = RiveViewModel(fileName: "import_seedphrase", autoPlay: true)
        }
        .onLoad(perform: startAnimations)
        .onDisappear {
            animationVM?.stop()
            animationVM = nil
        }
    }

    var informationView: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 12) {
                Text("beforeYouStart".localized)
                    .foregroundStyle(Theme.colors.textSecondary)
                    .font(Theme.fonts.caption12)

                CustomHighlightText(
                    "youAreEnteringAnewEra".localized,
                    highlight: "youAreEnteringAnewEraHighlight".localized,
                    style: LinearGradient.primaryGradientHorizontal
                )
                .foregroundStyle(Theme.colors.textPrimary)
                .font(Theme.fonts.title2)
                .frame(maxWidth: 330, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 24) {
                OnboardingInformationRowView(
                    title: "yourSeedphrase".localized,
                    subtitle: "yourSeedphraseSubtitle".localized,
                    icon: "seedphrase"
                )

                OnboardingInformationRowView(
                    title: "atLeastOneDevice".localized,
                    subtitle: "atLeastOneDeviceSubtitle".localized,
                    icon: "devices"
                )
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    func startAnimations() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation(.interpolatingSpring) {
                showInformation = true
            }

            withAnimation(.interpolatingSpring.delay(0.7)) {
                informationOpacity = 1
            }
        }
    }
}

#Preview {
    KeyImportOnboardingScreen()
}
