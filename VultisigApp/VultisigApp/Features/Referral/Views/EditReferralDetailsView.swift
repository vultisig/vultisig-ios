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
            VStack(spacing: 16) {
                yourReferralCodeSection
                GradientListSeparator()
                extendExpirationSection
                GradientListSeparator()
                choosePayoutAsset
                GradientListSeparator()
                summary
            }
        }
    }

    var yourReferralCodeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("yourReferralCode".localized)
                .foregroundStyle(Theme.colors.textPrimary)
                .font(Theme.fonts.bodySMedium)
                .frame(maxWidth: .infinity, alignment: .leading)
            ReferralTextField(
                text: .constant(viewModel.referralCode),
                placeholderText: .empty,
                action: .Copy,
                isDisabled: true
            )
        }
    }

    var extendExpirationSection: some View {
        VStack(spacing: 8) {
            setExpirationTitle
            CounterView(count: $viewModel.extendedCount, minimumValue: 0)
            expirationDate
        }
    }

    var setExpirationTitle: some View {
        Text(NSLocalizedString("extendExpiration(inYears)", comment: ""))
            .foregroundStyle(Theme.colors.textPrimary)
            .font(Theme.fonts.bodySMedium)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var expirationDate: some View {
        getCell(
            title: "expirationDate",
            description1: viewModel.extendedExpirationDate,
            description2: "",
            redactedDesc2: "",
            isPlaceholder: .constant(viewModel.extendedCount == 0)
        )
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
            .font(Theme.fonts.bodySMedium)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var choosePayoutAssetSelection: some View {
        Button {
            showPreferredAssetSelection = true
        } label: {
            ContainerView {
                HStack {
                    selectedAsset
                    Spacer()
                    Icon(named: "arrow", color: Theme.colors.textPrimary, size: 24)
                }
            }
        }
    }

    var summary: some View {
        VStack(spacing: 16) {
            getCell(
                title: "costs".localized,
                description1: viewModel.totalFeeAmountText,
                description2: viewModel.totalFeeFiatAmountText,
                isPlaceholder: $viewModel.loadingFees
            )
        }
    }

    var button: some View {
        PrimaryButton(title: "saveChanges") {
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
        HStack(spacing: 8) {
            AsyncImageView(
                logo: viewModel.preferredAsset?.asset.logo ?? "rune",
                size: CGSize(width: 32, height: 32),
                ticker: viewModel.preferredAsset?.asset.ticker ?? .empty,
                tokenChainLogo: viewModel.preferredAsset?.asset.chain.logo ?? .empty
            )

            Text(viewModel.preferredAsset?.asset.ticker ?? "RUNE")
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textPrimary)
        }
    }

    var infoLabel: some View {
        Image(systemName: "info.circle")
            .font(Theme.fonts.bodyLMedium)
            .foregroundStyle(Theme.colors.textPrimary)
    }

    private func getCell(
        title: String,
        description1: String,
        description2: String,
        redactedDesc1: String = "10 RUNE",
        redactedDesc2: String = "USD 10",
        isPlaceholder: Binding<Bool>
    ) -> some View {
        HStack {
            Text(NSLocalizedString(title, comment: ""))
                .foregroundStyle(Theme.colors.textTertiary)

            Spacer()

            VStack(alignment: .trailing, spacing: 0) {
                RedactedText(description1, redactedText: redactedDesc1, isLoading: isPlaceholder)
                    .foregroundStyle(Theme.colors.textPrimary)

                if !description2.isEmpty {
                    RedactedText(description2, redactedText: redactedDesc2, isLoading: isPlaceholder)
                        .foregroundStyle(Theme.colors.textTertiary)
                }
            }
        }
        .font(Theme.fonts.bodySMedium)
    }
}
