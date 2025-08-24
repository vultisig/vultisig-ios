//
//  ReferralMainScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 05/08/2025.
//

import SwiftUI
import SwiftData

struct ReferralMainScreen: View {
    @Query var vaults: [Vault]
    @ObservedObject var referredViewModel: ReferredViewModel
    @ObservedObject var referralViewModel: ReferralViewModel
    
    @State var showReferralCodeCopied = false
    @State var presentEditReferredScreen = false
    
    var body: some View {
        Screen(title: "referral".localized) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    createReferralBanner
                        .showIf(!referralViewModel.hasReferralCode)
                    createReferredBanner
                        .showIf(!referredViewModel.hasReferredCode)
                    referredCodeSection
                        .showIf(referredViewModel.hasReferredCode)
                    referralCodeSection
                        .showIf(referralViewModel.hasReferralCode)
                }
            }
        }
        .overlay(PopupCapsule(text: "referralCodeCopied", showPopup: $showReferralCodeCopied))
        .navigationDestination(isPresented: $presentEditReferredScreen) {
            ReferredCodeFormScreen(referredViewModel: referredViewModel, referralViewModel: referralViewModel)
        }
        .onLoad {
            Task {
                await referralViewModel.fetchReferralCodeDetails(vaults: vaults)
            }
        }
    }
    
    var createReferralBanner: some View {
        NavigationLink {
            ReferralTransactionFlowScreen(referralViewModel: referralViewModel, isEdit: false)
        } label: {
            BannerView(bgImage: "referral-banner") {
                VStack(alignment: .leading) {
                    HighlightedText(
                        localisedKey: "createYourCodeAndEarn",
                        highlightedText: "20%"
                    ) {
                        $0.font = Theme.fonts.bodyMMedium
                        $0.foregroundColor = Theme.colors.textPrimary
                    } highlightedTextStyle: {
                        $0.foregroundColor = Theme.colors.primaryAccent4
                    }
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: 175, alignment: .leading)
                }
            }
        }
    }
    
    var createReferredBanner: some View {
        NavigationLink {
            ReferredCodeFormScreen(referredViewModel: referredViewModel, referralViewModel: referralViewModel)
        } label: {
            BannerView(bgImage: "referral-banner") {
                VStack(alignment: .leading, spacing: 2) {
                    HighlightedText(
                        localisedKey: "saveOnSwaps",
                        highlightedText: "10%"
                    ) {
                        $0.font = Theme.fonts.caption12
                        $0.foregroundColor = Theme.colors.textExtraLight
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
            collectedRewardsView
            yourReferralCodeView
            expiresOnView
            editReferralButton
        }
        .background(BlurredBackground())
        .containerStyle(padding: 14)
    }
    
    var yourReferralCodeView: some View {
        ReferralCodeBoxView(
            title: "yourReferralCode".localized,
            value: referralViewModel.savedGeneratedReferralCode,
            icon: "copy"
        ) {
            showReferralCodeCopied = true
        }
    }
    
    var collectedRewardsView: some View {
        BannerView(bgImage: "referral-banner-2") {
            VStack(alignment: .leading, spacing: 2) {
                Icon(named: "trophy")
                    .padding(.bottom, 10)
                Text("collectedRewards".localized)
                    .foregroundStyle(Theme.colors.textExtraLight)
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
                .foregroundStyle(Theme.colors.textExtraLight)
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
        PrimaryNavigationButton(title: "editReferral") {
            ReferralTransactionFlowScreen(referralViewModel: referralViewModel, isEdit: true)
        }
        .disabled(!referralViewModel.canEditCode)
    }
    
    var referredCodeSection: some View {
        ReferralCodeBoxView(
            title: "yourFriendsReferralCode".localized,
            value: referredViewModel.savedReferredCode,
            icon: "pencil"
        ) {
            presentEditReferredScreen = true
        }
        .containerStyle(padding: 14)
    }
    
    var yourVaultView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("vaultSelected".localized)
                .foregroundStyle(Theme.colors.textPrimary)
                .font(Theme.fonts.bodySMedium)
            
            Button(action: {}) {
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
    ReferralMainScreen(referredViewModel: ReferredViewModel(), referralViewModel: ReferralViewModel())
}
