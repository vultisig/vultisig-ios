//
//  ReferralMainScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 05/08/2025.
//

import SwiftUI
import SwiftData

struct ReferralMainScreen: View {
    @StateObject var referredViewModel = ReferredViewModel()
    @StateObject var referralViewModel = ReferralViewModel()

    @StateObject var vaultSelectionViewModel = VaultSelectedViewModel()
    @State var showReferralCodeCopied = false
    @Environment(\.router) var router
    
    @EnvironmentObject var appViewModel: AppViewModel

    private let referralSavePercentage: String = "10%"
    
    var body: some View {
        Screen(title: "referral".localized) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    createReferredBanner
                        .showIf(!referredViewModel.hasReferredCode)
                    referredCodeSection
                        .showIf(referredViewModel.hasReferredCode)
                    referralCodeSection
                }
            }
        }
        .overlay(PopupCapsule(text: "referralCodeCopied", showPopup: $showReferralCodeCopied))
        .onLoad {
            vaultSelectionViewModel.selectedVault = appViewModel.selectedVault
            Task {
                await referralViewModel.fetchReferralCodeDetails()
            }
        }
        .onChange(of: vaultSelectionViewModel.selectedVault) { _, newValue in
            referralViewModel.currentVault = newValue
            referredViewModel.currentVault = newValue
            Task {
                await referralViewModel.fetchReferralCodeDetails()
            }
        }
    }

    var createReferredBanner: some View {
        Button {
            router.navigate(to: ReferralRoute.referredCodeForm)
        } label: {
            BannerView(bgImage: "referral-banner") {
                VStack(alignment: .leading, spacing: 2) {
                    HighlightedText(
                        text: String(format: "saveOnSwaps".localized, referralSavePercentage),
                        highlightedText: referralSavePercentage
                    ) {
                        $0.font = Theme.fonts.caption12
                        $0.foregroundColor = Theme.colors.textTertiary
                    } highlightedTextStyle: {
                        $0.foregroundColor = Theme.colors.primaryAccent4
                    }

                    Text("addFriendsReferral".localized)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .font(Theme.fonts.bodySMedium)
                }
            }
        }
    }
    
    var referralCodeSection: some View {
        VStack(spacing: 14) {
            yourVaultView
            
            if referralViewModel.hasReferralCode {
                referralCodeDetailsView
            } else {
                noReferralYetView
            }
        }
        .background(BlurredBackground())
        .containerStyle(padding: 14)
    }
    
    @ViewBuilder
    var referralCodeDetailsView: some View {
        collectedRewardsView
        yourReferralCodeView
        expiresOnView
        editReferralButton
    }
    
    var noReferralYetView: some View {
        VStack(spacing: 20) {
            Icon(named: "file-question", color: Theme.colors.primaryAccent4, size: 24)
                .padding(7)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.colors.bgSurface1))
                .padding(.top, 24)
            
            VStack(spacing: 8) {
                Text("noReferralYetTitle".localized)
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                Text("noReferralYetDescription".localized)
                    .font(Theme.fonts.footnote)
                    .foregroundStyle(Theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            PrimaryButton(title: "createReferral".localized) {
                router.navigate(to: ReferralRoute.createReferral(selectedVaultViewModel: vaultSelectionViewModel))
            }
            .padding(.bottom, 12)
        }
        .containerStyle(padding: 12, bgColor: .clear)
    }
    
    var yourReferralCodeView: some View {
        ReferralCodeBoxView(
            title: "yourReferralCode".localized,
            value: referralViewModel.savedReferralCode,
            icon: "copy"
        ) {
            ClipboardManager.copyToClipboard(referralViewModel.savedReferralCode)
            showReferralCodeCopied = true
        }
    }
    
    var collectedRewardsView: some View {
        BannerView(bgImage: "referral-banner-2") {
            VStack(alignment: .leading, spacing: 2) {
                Icon(named: "trophy")
                    .padding(.bottom, 10)
                Text("collectedRewards".localized)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .font(Theme.fonts.bodySMedium)
                RedactedText(
                    referralViewModel.collectedRewards,
                    redactedText: "10 RUNE",
                    isLoading: $referralViewModel.isLoading
                )
                .foregroundStyle(Theme.colors.textPrimary)
                .font(Theme.fonts.bodyLMedium)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    var expiresOnView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("expiresOn".localized)
                .foregroundStyle(Theme.colors.textTertiary)
                .font(Theme.fonts.bodySMedium)
            RedactedText(
                referralViewModel.expiresOn,
                redactedText: "01 Jan 2000",
                isLoading: $referralViewModel.isLoading
            )
            .foregroundStyle(Theme.colors.textPrimary)
            .font(Theme.fonts.bodyLMedium)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerStyle(padding: 14)
    }
    
    var editReferralButton: some View {
        PrimaryButton(title: "editReferral") {
            router.navigate(
                to: ReferralRoute.editReferral(
                    selectedVaultViewModel: vaultSelectionViewModel,
                    thornameDetails: referralViewModel.thornameDetails,
                    currentBlockheight: referralViewModel.currentBlockheight
                )
            )
        }
        .disabled(!referralViewModel.canEditCode)
    }
    
    var referredCodeSection: some View {
        ReferralCodeBoxView(
            title: "yourFriendsReferralCode".localized,
            value: referredViewModel.savedReferredCode,
            icon: "pencil"
        ) {
            router.navigate(to: ReferralRoute.referredCodeForm)
        }
        .containerStyle(padding: 14)
    }
    
    var yourVaultView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("vaultSelected".localized)
                .foregroundStyle(Theme.colors.textPrimary)
                .font(Theme.fonts.bodySMedium)
            
            Button {
                router.navigate(to: ReferralRoute.vaultSelection(selectedVaultViewModel: vaultSelectionViewModel))
            } label: {
                HStack(spacing: 10) {
                    Image("vault-icon")
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                        .frame(width: 28)
                    
                    Text(referralViewModel.yourVaultName ?? "")
                        .foregroundStyle(Theme.colors.textPrimary)
                        .font(Theme.fonts.bodyMMedium)
                    Spacer()
                    Icon(
                        named: "chevron-right",
                        color: Theme.colors.textPrimary,
                        size: 16
                    )
                }
                .containerStyle(padding: 12, radius: 99)
                .contentShape(Rectangle())
            }
        }
    }
}

struct ReferralCodeBoxView: View {
    let title: String
    let value: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .foregroundStyle(Theme.colors.textPrimary)
                .font(Theme.fonts.bodySMedium)
            
            Button(action: action) {
                HStack {
                    Text(value)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .font(Theme.fonts.bodyMMedium)
                    Spacer()
                    Icon(
                        named: icon,
                        color: Theme.colors.textPrimary,
                        size: 24
                    )
                }
                .padding(16)
                .containerStyle()
                .contentShape(Rectangle())
            }
        }
    }
}

#Preview {
    ReferralMainScreen()
}
