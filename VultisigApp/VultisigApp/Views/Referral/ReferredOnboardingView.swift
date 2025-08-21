//
//  ReferredOnboardingView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-27.
//

import SwiftUI

struct ReferredOnboardingView: View {
    @ObservedObject var referredViewModel: ReferredViewModel
    
    var body: some View {
        Screen(title: "referral".localized) {
            VStack {
                ScrollView {
                    StepsAnimationView(title: "howItWorks".localized, steps: 4) { animationCell(index: $0)
                    } header: {
                        animationHeader
                    }

                }
                
                button
            }
            .background(shadow)
        }
    }
    
    var shadow: some View {
        Circle()
            .frame(width: 360, height: 360)
            .foregroundColor(Theme.colors.alertInfo)
            .opacity(0.05)
            .blur(radius: 20)
    }
    
    var button: some View {
        PrimaryButton(title: "getStarted") {
            referredViewModel.showReferralDashboard()
        }
    }
    
    @ViewBuilder
    func animationCell(index: Int) -> some View {
        switch index {
        case 0:
            cellView(
                icon: "dots.and.line.vertical.and.cursorarrow.rectangle",
                title: "referralOnboardingTitle1",
                description: "referralOnboardingDescription1"
            )
        case 1:
            cellView(
                icon: "shareplay",
                title: "referralOnboardingTitle2",
                description: "referralOnboardingDescription2"
            )
        case 2:
            cellView(
                icon: "trophy",
                title: "referralOnboardingTitle3",
                description: "referralOnboardingDescription3"
            )
        case 3:
            cellView(
                icon: "person.badge.shield.checkmark",
                title: "referralOnboardingTitle4",
                description: "referralOnboardingDescription4"
            )
        default:
            EmptyView()
        }
    }
    
    func cellView(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(Theme.colors.primaryAccent4)
                .font(Theme.fonts.bodyLMedium)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString(title, comment: ""))
                    .font(Theme.fonts.bodySMedium)
                
                Text(NSLocalizedString(description, comment: ""))
                    .font(Theme.fonts.caption10)
            }
            .foregroundColor(Theme.colors.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    var animationHeader: some View {
        HStack {
            Image(systemName: "horn")
                .foregroundColor(Theme.colors.alertInfo)
            Text(NSLocalizedString("referralProgram", comment: ""))
                .foregroundColor(Theme.colors.textExtraLight)
                .font(Theme.fonts.caption12)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Theme.colors.bgSecondary)
        .cornerRadius(32)
        .overlay(
            RoundedRectangle(cornerRadius: 32)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
        .offset(x: -2)
    }
}

#Preview {
    ReferredOnboardingView(referredViewModel: ReferredViewModel())
}
