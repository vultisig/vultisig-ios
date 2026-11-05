//
//  PickReferralCode.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-09.
//

import SwiftUI

struct PickReferralCode: View {
    @Bindable var viewModel: ReferralDetailsViewModel

    var body: some View {
        return VStack(spacing: 14) {
            VStack(spacing: 8) {
                pickReferralTitle

                HStack(alignment: .top, spacing: 8) {
                    pickReferralTextfield
                    searchButton
                }
            }

            status
                .animation(.easeInOut, value: viewModel.availabilityStatus != nil)
        }
    }

    var pickReferralTitle: some View {
        Text(NSLocalizedString("pickReferralCode", comment: ""))
            .foregroundStyle(Theme.colors.textPrimary)
            .settingsText(.bodyS)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var pickReferralTextfield: some View {
        ReferralTextField(
            text: $viewModel.referralCode,
            placeholderText: "enter4Characters",
            action: .None,
            errorMessage: $viewModel.referralAvailabilityErrorMessage,
            showSuccess: viewModel.availabilityStatus == .available,
            showInvalid: viewModel.availabilityStatus == .alreadyTaken
        )
        .layoutPriority(1)
        .frame(maxWidth: .infinity)
        .onChange(of: viewModel.referralCode) { _, _ in
            viewModel.resetReferralData()
        }
    }

    var searchButton: some View {
        PrimaryButton(title: "search".localized, size: .squared) {
            Task {
                await viewModel.verifyReferralCode()
            }
        }
        .disabled(viewModel.isLoading)
    }

    @ViewBuilder
    var status: some View {
        if let status = viewModel.availabilityStatus {
            HStack {
                Text(NSLocalizedString("status", comment: ""))
                    .settingsText(.bodyS)
                    .foregroundStyle(Theme.colors.textTertiary)

                Spacer()

                Text(status.description)
                    .settingsText(.footnote)
                    .foregroundStyle(status.color)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .surface(Theme.colors.bgSurface1, radius: Theme.radius.pill, borderWidth: 1.5)
            }
            .frame(minHeight: 52)
        }
    }
}
