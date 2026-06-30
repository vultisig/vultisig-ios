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
        return VStack(spacing: 8) {
            pickReferralTitle

            HStack(alignment: .center, spacing: 8) {
                pickReferralTextfield
                searchButton
            }

            status
                .animation(.easeInOut, value: viewModel.availabilityStatus != nil)
        }
    }

    var pickReferralTitle: some View {
        Text(NSLocalizedString("pickReferralCode", comment: ""))
            .foregroundStyle(Theme.colors.textPrimary)
            .font(Theme.fonts.bodySMedium)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var pickReferralTextfield: some View {
        ReferralTextField(
            text: $viewModel.referralCode,
            placeholderText: "enter4Characters",
            action: .None,
            errorMessage: $viewModel.referralAvailabilityErrorMessage,
            showSuccess: viewModel.availabilityStatus == .available
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
        .scaledToFit()
        .disabled(viewModel.isLoading)
    }

    @ViewBuilder
    var status: some View {
        if let status = viewModel.availabilityStatus {
            HStack {
                Text(NSLocalizedString("status", comment: ""))
                    .foregroundStyle(Theme.colors.textTertiary)

                Spacer()

                Text(status.description)
                    .foregroundStyle(status.color)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .cornerRadius(24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Theme.colors.border, lineWidth: 1)
                    )
            }
            .font(Theme.fonts.bodySMedium)
            .padding(.top, 2)
        }
    }
}
