//
//  OnboardingYourVaultSetupScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 11/12/2025.
//

import SwiftUI
import RiveRuntime

struct OnboardingYourVaultSetupScreen: View {
    let tssType: TssType
    let keyImportInput: KeyImportInput?
    let setupType: KeyImportSetupType

    @State private var animationVM: RiveViewModel? = nil
    @State private var visibleRowCount = 0

    @Environment(\.router) var router

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("yourVaultSetup".localized)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .font(Theme.fonts.title2)
                    vaultTypeBadge
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 16)
                Spacer()
                animation
                Spacer()
                VStack(spacing: 32) {
                    informationView
                    PrimaryButton(title: "next") {
                        router.navigate(to: OnboardingRoute.vaultSetup(
                            tssType: tssType,
                            keyImportInput: keyImportInput,
                            setupType: setupType
                        ))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .screenEdgeInsets(.init(leading: 24, trailing: 24))
        .onLoad(perform: onLoad)
    }

    var animation: some View {
        animationVM?.view()
            .frame(maxWidth: 350, maxHeight: 240)
            .offset(x: -48)
    }

    var informationRows: [(title: String, subtitle: String, icon: String)] {
        [
            (feature1Title, feature1Description, "signature"),
            (feature2Title, feature2Description, "shield-check-filled"),
            (feature3Title, feature3Description, "lock")
        ]
    }

    var informationView: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(Array(informationRows.enumerated()), id: \.offset) { index, row in
                OnboardingInformationRowView(
                    title: row.title,
                    subtitle: row.subtitle,
                    icon: row.icon
                )
                .opacity(index < visibleRowCount ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: animateRows)
    }

    private func animateRows() {
        for index in informationRows.indices {
            let delay = Double(index + 1) * 0.4
            withAnimation(.linear(duration: 0.3).delay(delay)) {
                visibleRowCount = index + 1
            }
        }
    }

    var vaultTypeBadge: some View {
        HStack(spacing: 8) {
            vaultTypeBadgeIcon

            VStack(alignment: .leading, spacing: 0) {
                Text(vaultSetupTitle)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .font(Theme.fonts.subtitle)

                Text(vaultSetupSubtitle)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .font(Theme.fonts.caption12)
            }
        }
        .padding(8)
        .padding(.trailing, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .inset(by: 0.5)
                .fill(Theme.colors.bgSurface1)
                .stroke(
                    LinearGradient(
                        colors: [Theme.colors.borderExtraLight, .white.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
    }

    var vaultTypeBadgeIcon: some View {
        ZStack {
            Circle()
                .inset(by: 1)
                .shadow(color: .black.opacity(0.5), radius: 5, y: 5)
            ZStack {
                Circle()
                    .fill(Theme.colors.bgPrimary)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 2.5)
                RadialGradient(
                    colors: [Color(hex: "5CA7FF"), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 12
                )
                .opacity(0.4)
                .frame(height: 12)
                .offset(y: 8)
                .blur(radius: 5)
                // Icon on top
                Image(featureIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
            }
            .clipShape(Circle())
        }
        .frame(width: 33, height: 33)
    }

    private func onLoad() {
        animationVM = RiveViewModel(fileName: setupType.vaultSetupAnimationName)
        animationVM?.fit = .fitHeight
    }
}

private extension OnboardingYourVaultSetupScreen {
    var vaultSetupTitle: String {
        switch setupType {
        case .fast:
            return "vaultSetup1Title".localized
        case .secure(let count):
            switch count {
            case 2:
                return "vaultSetup2Title".localized
            case 3:
                return "vaultSetup3Title".localized
            default:
                return "vaultSetup4Title".localized
            }
        }
    }

    var vaultSetupSubtitle: String {
        switch setupType {
        case .fast:
            return "vaultSetup1Subtitle".localized
        case .secure(let count):
            switch count {
            case 2:
                return "vaultSetup2Subtitle".localized
            case 3:
                return "vaultSetup3Subtitle".localized
            default:
                return "vaultSetup4Subtitle".localized
            }
        }
    }

    var feature1Title: String {
        switch setupType {
        case .fast:
            return "vaultSetup1Feature1Title".localized
        case .secure(let count):
            switch count {
            case 2:
                return "vaultSetup2Feature1Title".localized
            case 3:
                return "vaultSetup3Feature1Title".localized
            default:
                return "vaultSetup4Feature1Title".localized
            }
        }
    }

    var feature1Description: String {
        switch setupType {
        case .fast:
            return "vaultSetup1Feature1Description".localized
        case .secure(let count):
            switch count {
            case 2:
                return "vaultSetup2Feature1Description".localized
            case 3:
                return "vaultSetup3Feature1Description".localized
            default:
                return "vaultSetup4Feature1Description".localized
            }
        }
    }

    var feature2Title: String {
        switch setupType {
        case .fast:
            return "vaultSetup1Feature2Title".localized
        case .secure(let count):
            switch count {
            case 2:
                return "vaultSetup2Feature2Title".localized
            case 3:
                return "vaultSetup3Feature2Title".localized
            default:
                return "vaultSetup4Feature2Title".localized
            }
        }
    }

    var feature2Description: String {
        switch setupType {
        case .fast:
            return "vaultSetup1Feature2Description".localized
        case .secure(let count):
            switch count {
            case 2:
                return "vaultSetup2Feature2Description".localized
            case 3:
                return "vaultSetup3Feature2Description".localized
            default:
                return "vaultSetup4Feature2Description".localized
            }
        }
    }

    var feature3Title: String {
        switch setupType {
        case .fast:
            return "vaultSetup1Feature3Title".localized
        case .secure(let count):
            switch count {
            case 2:
                return "vaultSetup2Feature3Title".localized
            case 3:
                return "vaultSetup3Feature3Title".localized
            default:
                return "vaultSetup4Feature3Title".localized
            }
        }
    }

    var feature3Description: String {
        switch setupType {
        case .fast:
            return "vaultSetup1Feature3Description".localized
        case .secure(let count):
            switch count {
            case 2:
                return "vaultSetup2Feature3Description".localized
            case 3:
                return "vaultSetup3Feature3Description".localized
            default:
                return "vaultSetup4Feature3Description".localized
            }
        }
    }

    var featureIcon: String {
        switch setupType {
        case .fast:
            return "lightning-glossy"
        case .secure:
            return "shield-glossy"
        }
    }
}

#Preview {
    OnboardingYourVaultSetupScreen(
        tssType: .Keygen,
        keyImportInput: nil,
        setupType: .fast
    )
    .toolbar {
        ToolbarItem {
            Button("test") {}
        }
    }
    .frame(width: 1500)
    .frame(maxWidth: 1500, maxHeight: isMacOS ? 800 : nil)
}
