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
    
    var body: some View {
        Screen(title: "referral".localized) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    referralCodeSection
                    collectedRewardsSection
                    expiresOnSection
                    GradientListSeparator()
                    editReferralButtonSection
                    yourFriendsReferralCodeSection
                    changeFriendsReferralCodeSection
                }
            }
        }
        .onLoad {
            Task {
                await referralViewModel.fetchReferralCodeDetails(vaults: vaults)
            }
        }
    }
    
    var referralCodeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("yourReferralCode".localized)
                .foregroundColor(Theme.colors.textPrimary)
                .font(Theme.fonts.bodySMedium)
                .frame(maxWidth: .infinity, alignment: .leading)
            ReferralTextField(
                text: $referralViewModel.savedGeneratedReferralCode,
                placeholderText: .empty,
                action: .Copy,
                isDisabled: true
            )
        }
    }
    
    var collectedRewardsSection: some View {
        BoxView {
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
    
    var expiresOnSection: some View {
        BoxView {
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
        }
    }
    
    var editReferralButtonSection: some View {
        PrimaryNavigationButton(title: "editReferral") {
            ReferralTransactionFlowScreen(referralViewModel: referralViewModel, isEdit: true)
        }
        .disabled(!referralViewModel.canEditCode)
    }
    
    var yourFriendsReferralCodeSection: some View {
        Group {
            VStack(alignment: .leading, spacing: 8) {
                Text( "yourFriendsReferralCode".localized)
                    .foregroundColor(Theme.colors.textPrimary)
                    .font(Theme.fonts.bodySMedium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ReferralTextField(
                    text: $referredViewModel.savedReferredCode,
                    placeholderText: .empty,
                    action: .None,
                    isDisabled: true
                )
            }
            GradientListSeparator()
        }
        .showIf(referredViewModel.savedReferredCode.isNotEmpty)
    }
    
    var changeFriendsReferralCodeSection: some View {
        NavigationLink {
            EditReferredCodeView(referredViewModel: referredViewModel, referralViewModel: referralViewModel)
        } label: {
            BoxView {
                HStack {
                    VStack(alignment: .leading, spacing: 12) {
                        Icon(named: "undo-dot")
                        Text(referredViewModel.referredTitleText.localized)
                            .foregroundStyle(Theme.colors.textPrimary)
                            .font(Theme.fonts.bodySMedium)
                            .frame(maxWidth: 245)
                            .multilineTextAlignment(.leading)
                            .layoutPriority(1)
                    }
                    Spacer()
                    Icon(named: "arrow", color: Theme.colors.textPrimary, size: 24)
                }
            }
        }
    }
}


#Preview {
    ReferralMainScreen(referredViewModel: ReferredViewModel(), referralViewModel: ReferralViewModel())
}
