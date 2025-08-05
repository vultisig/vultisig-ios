//
//  ReferralMainScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 05/08/2025.
//

import SwiftUI

struct ReferralMainScreen: View {
    @State var referralCode: String = "TEST"
    @State var collectedRewards: String = "10.4 RUNE"
    @State var expiresOn: String = "25 May of 2027"
    @State var yourFriendsReferralCode: String = "XYZ"
    
    var body: some View {
        
        Screen(title: "referral".localized) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    referralCodeSection
                    collectedRewardsSection
                    expiresOnSection
                    PrimaryButton(title: "editReferral".localized) {
                        
                    }
                    GradientListSeparator()
                    yourFriendsReferralCodeSection
                    GradientListSeparator()
                    changeFriendsReferralCodeSection
                }
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
                text: $referralCode,
                placeholderText: .empty,
                action: .Copy,
                isDisabled: true
            )
        }
    }
    
    var collectedRewardsSection: some View {
        BoxView {
            VStack(alignment: .leading, spacing: 0) {
                Icon(named: "trophy")
                    .padding(.bottom, 12)
                Text("collectedRewards".localized)
                    .foregroundStyle(Color.extraLightGray)
                    .font(.body14BrockmannMedium)
                Text(collectedRewards)
                    .foregroundStyle(Color.neutral50)
                    .font(.body18BrockmannMedium)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    var expiresOnSection: some View {
        BoxView {
            VStack(alignment: .leading, spacing: 4) {
                Text("expiresOn".localized)
                    .foregroundStyle(Color.extraLightGray)
                    .font(.body14BrockmannMedium)
                Text(expiresOn)
                    .foregroundStyle(Color.neutral50)
                    .font(.body18BrockmannMedium)
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
                text: $yourFriendsReferralCode,
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
                    Image(systemName: "chevron.right")
                }
            }
        }
    }
    
    func onChangeFriendsReferralCode() {}
}


#Preview {
    ReferralMainScreen()
}
