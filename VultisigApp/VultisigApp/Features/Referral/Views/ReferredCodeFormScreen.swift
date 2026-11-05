//
//  ReferredCodeFormScreen.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-26.
//

import SwiftUI

struct ReferredCodeFormScreen: View {
    @StateObject var referredViewModel = ReferredViewModel()

    private let referralSavePercentage: String = "10%"
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appViewModel: AppViewModel

    var body: some View {
        Screen {
            VStack {
                main
                button
            }
        }
        .screenTitle(screenTitle)
        .withLoading(isLoading: $referredViewModel.isLoading)
        .onAppear {
            setData()
        }
        .onDisappear {
            referredViewModel.resetData()
        }
    }

    private var screenTitle: String {
        referredViewModel.hasReferredCode ? referredViewModel.title.localized : "saveReferralCardTitle".localized
    }

    var main: some View {
        ScrollView {
            VStack(spacing: 8) {
                HighlightedText(
                    text: String(format: "referredSaveOnSwaps".localized, referralSavePercentage),
                    highlightedText: referralSavePercentage
                ) {
                    $0.font = Theme.fonts.subtitle
                    $0.foregroundColor = Theme.colors.textSecondary
                } highlightedTextStyle: {
                    $0.foregroundColor = Theme.colors.primaryAccent4
                }
                .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
                .showIf(!referredViewModel.hasReferredCode)
                textField
            }
        }
        .foregroundStyle(Theme.colors.textPrimary)
    }

    var textField: some View {
        ReferralTextField(
            text: $referredViewModel.referredCode,
            placeholderText: "enterUpto4Characters",
            action: .Paste,
            errorMessage: $referredViewModel.referredLaunchViewErrorMessage
        )
    }

    var button: some View {
        PrimaryButton(title: "saveReferral", size: .compactSemibold) {
            Task { @MainActor in
                let codeUpdated = await referredViewModel.verifyAndSaveReferredCode()
                if codeUpdated {
                    dismiss()
                }
            }

        }
    }

    private func setData() {
        referredViewModel.currentVault = appViewModel.selectedVault
        referredViewModel.resetData()
        if referredViewModel.hasReferredCode {
            referredViewModel.referredCode = referredViewModel.savedReferredCode
        }
    }
}

#Preview {
    ReferredCodeFormScreen()
        .environmentObject(AppViewModel())
}
