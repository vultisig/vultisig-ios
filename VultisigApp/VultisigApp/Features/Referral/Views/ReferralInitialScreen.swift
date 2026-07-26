//
//  ReferralInitialScreen.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-29.
//

import SwiftUI

struct ReferralInitialScreen: View {
    @StateObject var referredViewModel = ReferredViewModel()
    @StateObject var referralViewModel = ReferralViewModel()

    @Environment(\.router) var router
    @EnvironmentObject var appViewModel: AppViewModel

    private let referredSavePercentage: String = "10%"
    private let createSavePercentage: String = "20%"

    var body: some View {
        Screen {
            VStack(spacing: 0) {
                Spacer()
                image
                Spacer()
                cards
            }
        }
        .screenTitle("vultisig-referrals".localized)
        .onAppear {
            referralViewModel.currentVault = appViewModel.selectedVault
            referredViewModel.currentVault = appViewModel.selectedVault
            referredViewModel.setData()
        }
        .onChange(of: referralViewModel.currentVault) { _, _ in
            // TODO: - Remove after release
            referredViewModel.migrateCodeIfNeeded()
            Task {
                await referralViewModel.fetchVaultData()
            }
        }
    }

    var image: some View {
        Image("referral-initial")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: 375)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black, location: 0.15),
                        .init(color: .black, location: 0.85),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .black, location: 0.1),
                            .init(color: .black, location: 0.9),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            )
    }

    var cards: some View {
        VStack(spacing: 14) {
            saveReferralCard
            createReferralCard
        }
    }

    var saveReferralCard: some View {
        ReferralEntryCard(
            iconName: .megaphone,
            title: "saveReferralCardTitle".localized,
            description: String(format: "saveReferralCardBody".localized, referredSavePercentage),
            highlightedText: referredSavePercentage,
            showActiveBadge: referredViewModel.hasReferredCode
        ) {
            router.navigate(to: ReferralRoute.referredCodeForm)
        }
    }

    @ViewBuilder
    var createReferralCard: some View {
        if referralViewModel.hasReferralCode {
            ReferralEntryCard(
                iconName: .userSparkle,
                title: "myReferralCardTitle".localized,
                description: "myReferralCardBody".localized,
                highlightedText: nil,
                showActiveBadge: false
            ) {
                router.navigate(to: ReferralRoute.main)
            }
        } else {
            ReferralEntryCard(
                iconName: .userSparkle,
                title: "createReferralCardTitle".localized,
                description: String(format: "createYourCodeAndEarn".localized, createSavePercentage),
                highlightedText: createSavePercentage,
                showActiveBadge: false
            ) {
                router.navigate(to: ReferralRoute.createReferral(selectedVaultViewModel: VaultSelectedViewModel()))
            }
        }
    }
}

private struct ReferralEntryCard: View {
    let iconName: ImageResource
    let title: String
    let description: String
    let highlightedText: String?
    let showActiveBadge: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Icon(iconName, color: Theme.colors.primaryAccent4, size: 24)
                        Text(title)
                            .font(Theme.fonts.title3)
                            .foregroundStyle(Theme.colors.textPrimary)
                        if showActiveBadge {
                            activeBadge
                        }
                    }
                    descriptionText
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Icon(
                    .chevronRight,
                    color: Theme.colors.textPrimary,
                    size: 20
                )
            }
            .padding(24)
            .background(Theme.colors.bgSurface1)
            .cornerRadius(16)
            .contentShape(Rectangle())
        }
    }

    @ViewBuilder
    var descriptionText: some View {
        if let highlightedText {
            HighlightedText(
                text: description,
                highlightedText: highlightedText
            ) {
                $0.font = Theme.fonts.footnote
                $0.foregroundColor = Theme.colors.textSecondary
            } highlightedTextStyle: {
                $0.foregroundColor = Theme.colors.primaryAccent4
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(description)
                .font(Theme.fonts.footnote)
                .foregroundStyle(Theme.colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var activeBadge: some View {
        Text("active".localized)
            .font(Theme.fonts.footnote)
            .foregroundStyle(Theme.colors.alertSuccess)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Theme.colors.alertSuccess.opacity(0.05))
            )
            .overlay(
                Capsule()
                    .stroke(Theme.colors.alertSuccess, lineWidth: 1)
            )
    }
}

#Preview {
    ReferralInitialScreen()
        .environmentObject(AppViewModel())
}
