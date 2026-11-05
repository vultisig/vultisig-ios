//
//  EditReferralDetailsView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 06/08/2025.
//

import SwiftUI

struct EditReferralDetailsView: View {
    @State var viewModel: EditReferralDetailsViewModel
    var onNext: (SendTransaction) -> Void

    @EnvironmentObject var homeViewModel: HomeViewModel

    @State private var showPreferredAssetSelection: Bool = false

    init(
        viewModel: EditReferralDetailsViewModel,
        onNext: @escaping (SendTransaction) -> Void
    ) {
        self._viewModel = State(initialValue: viewModel)
        self.onNext = onNext
    }

    var body: some View {
        Screen {
            content
        }
        .screenTitle("editReferral".localized)
        .crossPlatformSheet(isPresented: $showPreferredAssetSelection) {
            PreferredAssetSelectionView(isPresented: $showPreferredAssetSelection, preferredAsset: $viewModel.preferredAsset) {
                showPreferredAssetSelection = false
            }
        }
        .alert(isPresented: $viewModel.hasError) {
            alert
        }
        .onLoad {
            Task {
                await viewModel.setup()
            }
        }
    }

    var content: some View {
        VStack {
            main
            button
        }
    }

    var main: some View {
        ScrollView {
            VStack(spacing: 14) {
                yourReferralCodeSection
                separator
                extendExpirationSection
                separator
                choosePayoutAsset
                separator
                summary
            }
        }
    }

    var yourReferralCodeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("yourReferralCode".localized)
                .foregroundStyle(Theme.colors.textTertiary)
                .settingsText(.bodyS)
                .frame(maxWidth: .infinity, alignment: .leading)
            ReferralTextField(
                text: .constant(viewModel.referralCode),
                placeholderText: .empty,
                action: .Copy,
                isDisabled: true,
                appearance: .settings
            )
        }
    }

    var separator: some View {
        Separator(color: Theme.colors.borderLight, opacity: 1)
            .padding(.vertical, -0.5) // Takes the line out of the 14pt rhythm, as in the design.
    }

    var extendExpirationSection: some View {
        VStack(spacing: 14) {
            VStack(spacing: 8) {
                setExpirationTitle
                CounterView(count: $viewModel.extendedCount, minimumValue: 0)
            }
            expirationDate
        }
    }

    var setExpirationTitle: some View {
        Text(NSLocalizedString("extendExpiration(inYears)", comment: ""))
            .foregroundStyle(Theme.colors.textPrimary)
            .settingsText(.bodyS)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var expirationDate: some View {
        HStack {
            Text("newExpirationDate".localized)
            Spacer()
            Text(viewModel.extendedCount == 0 ? "-" : viewModel.extendedExpirationDate)
        }
        .settingsText(.caption)
        .foregroundStyle(Theme.colors.textPrimary)
    }

    var choosePayoutAsset: some View {
        VStack(spacing: 8) {
            choosePayoutAssetTitle
            choosePayoutAssetSelection
        }
    }

    var choosePayoutAssetTitle: some View {
        Text(NSLocalizedString("choosePayoutAsset", comment: ""))
            .foregroundStyle(Theme.colors.textPrimary)
            .settingsText(.bodyS)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var choosePayoutAssetSelection: some View {
        Button {
            showPreferredAssetSelection = true
        } label: {
            HStack {
                selectedAsset
                Spacer()
                Icon(.chevronRightSmall, color: Theme.colors.textPrimary, size: 20)
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .surface(Theme.colors.bgSurface1, radius: Theme.radius.md)
            .contentShape(Theme.radius.md.shape)
        }
        .buttonStyle(.plain)
    }

    var summary: some View {
        HStack {
            Text("costs".localized)
                .settingsText(.footnote)
                .foregroundStyle(Theme.colors.textTertiary)

            Spacer()

            VStack(alignment: .trailing, spacing: 0) {
                RedactedText(viewModel.totalFeeAmountText, redactedText: "10 RUNE", isLoading: $viewModel.loadingFees)
                    .settingsText(.bodyS)
                    .foregroundStyle(Theme.colors.textPrimary)

                if !viewModel.totalFeeFiatAmountText.isEmpty {
                    RedactedText(viewModel.totalFeeFiatAmountText, redactedText: "USD 10", isLoading: $viewModel.loadingFees)
                        .settingsText(.bodyS)
                        .foregroundStyle(Theme.colors.textTertiary)
                }
            }
        }
    }

    var button: some View {
        PrimaryButton(title: "saveChanges", size: .compact) {
            guard let tx = viewModel.verifyReferralEntries() else {
                return
            }
            onNext(tx)
        }
        .disabled(!viewModel.isValidForm)
    }

    var alert: Alert {
        Alert(
            title: Text(NSLocalizedString("error", comment: "")),
            message: Text(viewModel.errorMessage ?? .empty),
            dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
        )
    }

    var selectedAsset: some View {
        HStack(spacing: 6) {
            AsyncImageView(
                logo: viewModel.preferredAsset?.asset.logo ?? (hasUnresolvedPayoutAsset ? .empty : "rune"),
                size: CGSize(width: 32, height: 32),
                ticker: viewModel.preferredAsset?.asset.ticker ?? .empty,
                tokenChainLogo: viewModel.preferredAsset?.asset.tokenChainLogo
            )

            Text(payoutAssetLabel)
                .settingsText(.bodyM)
                .foregroundStyle(Theme.colors.textPrimary)
        }
    }

    /// The THORName names a payout asset this app could not map to a coin.
    private var hasUnresolvedPayoutAsset: Bool {
        let stored = viewModel.thornameDetails.preferredAsset
        return viewModel.preferredAsset == nil && !stored.isEmpty && !viewModel.thornameDetails.isDefaultPreferredAsset
    }

    /// Never prints RUNE for a name that pays out in something else.
    private var payoutAssetLabel: String {
        if let asset = viewModel.preferredAsset {
            return asset.asset.ticker
        }
        return hasUnresolvedPayoutAsset ? viewModel.thornameDetails.preferredAsset : "RUNE"
    }

    var infoLabel: some View {
        Image(systemName: "info.circle")
            .font(Theme.fonts.bodyLMedium)
            .foregroundStyle(Theme.colors.textPrimary)
    }
}
