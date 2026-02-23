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

    var body: some View {
        Screen {
            VStack {
                main
                button
            }
        }
        .screenTitle(referredViewModel.title.localized)
        .overlay(referredViewModel.isLoading ? loader : nil)
        .onAppear {
            setData()
        }
        .onDisappear {
            referredViewModel.resetData()
        }
    }

    var main: some View {
        ScrollView {
            VStack(spacing: 8) {
                HighlightedText(
                    text: String(format: "referredSaveOnSwaps".localized, referralSavePercentage),
                    highlightedText: referralSavePercentage
                ) {
                    $0.font = Theme.fonts.bodySMedium
                    $0.foregroundColor = Theme.colors.textPrimary
                } highlightedTextStyle: {
                    $0.foregroundColor = Theme.colors.primaryAccent4
                }
                .showIf(!referredViewModel.hasReferredCode)
                textField
            }
        }
        .foregroundColor(Theme.colors.textPrimary)
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
        PrimaryButton(title: "saveReferral") {
            Task { @MainActor in
                let codeUpdated = await referredViewModel.verifyAndSaveReferredCode()
                if codeUpdated {
                    dismiss()
                }
            }

        }
    }

    var loader: some View {
        Loader()
    }

    private func setData() {
        referredViewModel.resetData()
        if referredViewModel.hasReferredCode {
            referredViewModel.referredCode = referredViewModel.savedReferredCode
        }
    }
}

#Preview {
    ReferredCodeFormScreen()
}
