//
//  ReferralMainScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 05/08/2025.
//

import SwiftUI
import VultisigUIResources
import SwiftData

struct ReferralMainScreen: View {
    @StateObject var referredViewModel = ReferredViewModel()
    @StateObject var referralViewModel = ReferralViewModel()

    @StateObject var vaultSelectionViewModel = VaultSelectedViewModel()
    @State var showReferralCodeCopied = false
    @Environment(\.router) var router

    @EnvironmentObject var appViewModel: AppViewModel

    private let referralSavePercentage: String = "10%"
    /// Off the scale on purpose: the design's empty state sits between lg and xl.
    private let emptyStateRadius: CGFloat = 20 // swiftlint:disable:this no_raw_corner_radius

    var body: some View {
        Screen {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    createReferredBanner
                        .showIf(!referredViewModel.hasReferredCode)
                    referredCodeSection
                        .showIf(referredViewModel.hasReferredCode)
                    referralCodeSection
                }
            }
            .background(SettingsGlowBackground(tint: .referral, verticalOffset: 0))
        }
        .screenTitle("myReferralCardTitle".localized)
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
                    .settingsText(.caption)

                    Text("addFriendsReferral".localized)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .settingsText(.bodyS)
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
        .referralPanel()
    }

    @ViewBuilder
    var referralCodeDetailsView: some View {
        collectedRewardsView
        yourReferralCodeView
        expiresOnView
        editReferralButton
    }

    var noReferralYetView: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                Icon(.circleDashed2, color: Theme.colors.primaryAccent4, size: 24)

                VStack(spacing: 8) {
                    Text("noReferralYetTitle".localized)
                        .settingsText(.title3)
                        .foregroundStyle(Theme.colors.textPrimary)
                    Text("noReferralYetDescription".localized)
                        .settingsText(.footnote)
                        .foregroundStyle(Theme.colors.textTertiary)
                }
                .multilineTextAlignment(.center)
            }

            PrimaryButton(
                title: "createReferral".localized,
                leadingView: {
                    Icon(.plus, color: Theme.colors.textPrimary, size: 10)
                        .frame(width: 16, height: 16)
                },
                trailingView: { EmptyView() },
                size: .pill,
                action: {
                    router.navigate(to: ReferralRoute.createReferral(selectedVaultViewModel: vaultSelectionViewModel))
                }
            )
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .background(Theme.colors.bgSurface1)
        .clipShape(RoundedRectangle(cornerRadius: emptyStateRadius, style: .continuous))
    }

    var yourReferralCodeView: some View {
        ReferralCodeBoxView(
            title: "yourReferralCode".localized,
            value: referralViewModel.savedReferralCode,
            icon: .copies3Filled
        ) {
            ClipboardManager.copyToClipboard(referralViewModel.savedReferralCode)
            showReferralCodeCopied = true
        }
    }

    var collectedRewardsView: some View {
        BannerView(bgImage: "referral-banner-2", radius: Theme.radius.md, padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Icon(.trophy, color: Theme.colors.textPrimary, size: 20)
                VStack(alignment: .leading, spacing: 0) {
                    Text("collectedRewards".localized)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .settingsText(.bodyS)
                    RedactedText(
                        referralViewModel.collectedRewards,
                        redactedText: "10 RUNE",
                        isLoading: $referralViewModel.isLoading
                    )
                    .foregroundStyle(Theme.colors.textPrimary)
                    .settingsText(.bodyL)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var expiresOnView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("expiresOn".localized)
                .foregroundStyle(Theme.colors.textTertiary)
                .settingsText(.bodyS)
            RedactedText(
                referralViewModel.expiresOn,
                redactedText: "01 Jan 2000",
                isLoading: $referralViewModel.isLoading
            )
            .foregroundStyle(Theme.colors.textPrimary)
            .settingsText(.bodyL)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .surface(Theme.colors.bgPrimary, radius: Theme.radius.md)
    }

    var editReferralButton: some View {
        PrimaryButton(title: "editReferral", size: .compactSemibold) {
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
            icon: .penWritingFilled
        ) {
            router.navigate(to: ReferralRoute.referredCodeForm)
        }
        .referralPanel()
    }

    var yourVaultView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("vaultSelected".localized)
                .foregroundStyle(Theme.colors.textPrimary)
                .settingsText(.bodyS)

            Button {
                router.navigate(to: ReferralRoute.vaultSelection(selectedVaultViewModel: vaultSelectionViewModel))
            } label: {
                HStack(spacing: 10) {
                    VultisigImage("vault-icon")
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                        .frame(width: 28)

                    Text(referralViewModel.yourVaultName ?? "")
                        .foregroundStyle(Theme.colors.textPrimary)
                        .font(Theme.fonts.bodyMRegular)
                    Spacer()
                    Icon(
                        .chevronRightSmall,
                        color: Theme.colors.textPrimary,
                        size: 16
                    )
                }
                .padding(.horizontal, 12)
                .frame(height: 48)
                .surface(Theme.colors.bgPrimary, radius: Theme.radius.pill)
                .contentShape(Rectangle())
            }
        }
    }
}

struct ReferralCodeBoxView: View {
    let title: String
    let value: String
    let icon: ImageResource
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .foregroundStyle(Theme.colors.textTertiary)
                .settingsText(.bodyS)

            Button(action: action) {
                HStack {
                    Text(value)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .settingsText(.bodyS)
                    Spacer()
                    Icon(
                        icon,
                        color: Theme.colors.textPrimary,
                        size: 20
                    )
                }
                .padding(16)
                .surface(Theme.colors.bgPrimary, radius: Theme.radius.lg, border: Theme.colors.borderExtraLight)
                .contentShape(Rectangle())
            }
        }
    }
}

private extension View {
    func referralPanel() -> some View {
        self
            .padding(14)
            .surface(Theme.colors.bgPrimary.opacity(0.5), radius: Theme.radius.xl)
    }
}

#Preview {
    ReferralMainScreen()
}
