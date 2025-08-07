//
//  ReferralMainScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 05/08/2025.
//

import SwiftUI

struct ReferralMainScreen: View {
    @ObservedObject var referredViewModel: ReferredViewModel
    @ObservedObject var referralViewModel: ReferralViewModel
    
    var body: some View {
        Screen(title: "referral".localized) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    referralCodeSection
                    collectedRewardsSection
                    expiresOnSection
                    PrimaryNavigationButton(title: "editReferral") {
                        ReferralTransactionFlowScreen(referralViewModel: referralViewModel, isEdit: true)
                    }
                    .disabled(!referralViewModel.canEditCode)
                    GradientListSeparator()
                    yourFriendsReferralCodeSection
                    GradientListSeparator()
                    changeFriendsReferralCodeSection
                }
            }
        }
        .onLoad {
            Task {
                await referralViewModel.fetchReferralCodeDetails()
            }
        }
    }
    
    var referralCodeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("yourReferralCode".localized)
                .foregroundColor(.neutral0)
                .font(.body14MontserratMedium)
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
                    .foregroundStyle(Color.extraLightGray)
                    .font(.body14BrockmannMedium)
                Text(referralViewModel.collectedRewards)
                    .foregroundStyle(Color.neutral50)
                    .font(.body18BrockmannMedium)
                    .redacted(reason: referralViewModel.isLoading ? .placeholder : [])
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    var expiresOnSection: some View {
        BoxView {
            VStack(alignment: .leading, spacing: 2) {
                Text("expiresOn".localized)
                    .foregroundStyle(Color.extraLightGray)
                    .font(.body14BrockmannMedium)
                Text(referralViewModel.expiresOn)
                    .foregroundStyle(Color.neutral50)
                    .font(.body18BrockmannMedium)
                    .redacted(reason: referralViewModel.isLoading ? .placeholder : [])
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    var yourFriendsReferralCodeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("yourFriendsReferralCode".localized)
                .foregroundColor(.neutral0)
                .font(.body14MontserratMedium)
                .frame(maxWidth: .infinity, alignment: .leading)
            ReferralTextField(
                text: $referredViewModel.savedReferredCode,
                placeholderText: .empty,
                action: .None,
                isDisabled: true
            )
        }
    }
    
    var changeFriendsReferralCodeSection: some View {
        Button(action: onChangeFriendsReferralCode) {
            BoxView {
                HStack {
                    VStack(alignment: .leading, spacing: 12) {
                        Icon(named: "undo-dot")
                        Text("changeFriendsReferralCode".localized)
                            .foregroundStyle(Color.neutral50)
                            .font(.body14BrockmannMedium)
                            .frame(maxWidth: 245)
                            .multilineTextAlignment(.leading)
                            .layoutPriority(1)
                    }
                    Spacer()
                    Icon(named: "arrow", color: Color.neutral0, size: 24)
                }
            }
        }
    }
    
    func onChangeFriendsReferralCode() {}
}


#Preview {
    ReferralMainScreen(referredViewModel: ReferredViewModel(), referralViewModel: ReferralViewModel())
}
