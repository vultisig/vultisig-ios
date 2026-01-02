//
//  KeyImportOverviewScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 11/12/2025.
//

import SwiftUI

struct KeyImportOverviewScreen: View {
    let vault: Vault
    let email: String?
    let keyImportInput: KeyImportInput?
    
    enum Page: Int, CaseIterable, Hashable {
        case multisig
        case vaultShares
    }
    
    @State private var scrollPosition: Page? = .multisig
    
    @State private var isVerificationLinkActive = false
    @Environment(\.router) var router
    
    var buttonTitle: String {
        "next".localized
    }
    
    var body: some View {
        Screen(edgeInsets: .init(leading: 0, trailing: 0)) {
            VStack(spacing: 0) {
                Spacer()
                ZStack {
                    if scrollPosition == .multisig {
                        Image("seed-phrase-overview-multisig")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image("seed-phrase-overview-vault-shares")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
                }
                .frame(maxWidth: 600, maxHeight: .infinity)
                .animation(.interpolatingSpring, value: scrollPosition)
                Spacer()
                VStack(spacing: 32) {
                    pages
                    pagesIndicator
                    PrimaryButton(title: buttonTitle) {
                        if scrollPosition == .multisig {
                            withAnimation(.interpolatingSpring) {
                                scrollPosition = .vaultShares
                            }
                        } else {
                            router.navigate(to: KeygenRoute.backupNow(
                                tssType: .KeyImport,
                                backupType: .single(vault: vault),
                                isNewVault: true
                            ))
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .crossPlatformSheet(isPresented: $isVerificationLinkActive) {
            ServerBackupVerificationView(
                tssType: .KeyImport,
                vault: vault,
                email: email ?? .empty,
                isPresented: $isVerificationLinkActive,
                tabIndex: .constant(0),
                onBackup: { },
                onBackToEmailSetup: {
                    router.navigate(to: OnboardingRoute.vaultSetup(
                        tssType: .KeyImport,
                        keyImportInput: keyImportInput
                    ))
                }
            )
        }
        .onLoad {
            if email != nil {
                isVerificationLinkActive = true
            }
        }
    }
    
    @ViewBuilder
    var pages: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Page.allCases, id: \.self) { page in
                    VStack(alignment: .leading, spacing: 24) {
                        switch page {
                        case .multisig:
                            multisigPageContent
                        case .vaultShares:
                            vaultSharesPageContent
                        }
                    }
                    .padding(.horizontal, 16)
                    .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $scrollPosition)
    }
    
    var pagesIndicator: some View {
        HStack(spacing: 4) {
            ForEach(Page.allCases, id: \.self) { page in
                let size: CGFloat = page == scrollPosition ? 5 : 4
                let color = page == scrollPosition
                ? Theme.colors.textPrimary : Theme.colors.textTertiary
                Circle()
                    .fill(color)
                    .frame(width: size, height: size)
                    .animation(.interpolatingSpring, value: page == scrollPosition)
            }
        }
    }
    
    var multisigPageContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            CustomHighlightText(
                "multisigTitle".localized,
                highlight: "multisigTitleHighlight".localized,
                style: LinearGradient.secondaryGradientHorizontal
            )
            .foregroundStyle(Theme.colors.textPrimary)
            .font(Theme.fonts.title2)
            
            OnboardingInformationRowView(
                title: "whatIsMultisig".localized,
                subtitle: "whatIsMultisigSubtitle".localized,
                icon: "four-square-circle"
            )
            
            OnboardingInformationRowView(
                title: "whySwitchFromSeedphrase".localized,
                subtitle: "whySwitchFromSeedphraseSubtitle".localized,
                icon: "folder-hexagon"
            )
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    
    var vaultSharesPageContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            CustomHighlightText(
                "vaultSharesTitle".localized,
                highlight: "vaultSharesTitleHighlight".localized,
                style: LinearGradient.secondaryGradientHorizontal
            )
            .foregroundStyle(Theme.colors.textPrimary)
            .font(Theme.fonts.title2)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("whatAreVaultShares".localized)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .font(Theme.fonts.subtitle)
                
                VStack(alignment: .leading, spacing: 0) {
                    Text("whatAreVaultSharesDescription".localized)
                        .foregroundStyle(Theme.colors.textTertiary)
                    Text("whatAreVaultSharesDescription2".localized)
                        .foregroundStyle(Theme.colors.textPrimary)
                }
                .font(Theme.fonts.footnote)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    KeyImportOverviewScreen(
        vault: .example,
        email: "",
        keyImportInput: nil
    )
}
