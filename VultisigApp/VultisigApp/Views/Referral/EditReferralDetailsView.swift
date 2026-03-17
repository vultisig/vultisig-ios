//
//  EditReferralDetailsView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 06/08/2025.
//

import SwiftUI

struct EditReferralDetailsView: View {
    @StateObject var viewModel: EditReferralViewModel
    @ObservedObject var sendTx: SendTransaction
    var onNext: () -> Void

    @EnvironmentObject var homeViewModel: HomeViewModel

    @State var showPreferredAssetSelection: Bool = false

    init(
        viewModel: EditReferralViewModel,
        sendTx: SendTransaction,
        onNext: @escaping () -> Void
    ) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.sendTx = sendTx
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
                .foregroundColor(Theme.colors.textPrimary)
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
            .foregroundColor(Theme.colors.textPrimary)
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
            .foregroundColor(Theme.colors.textPrimary)
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
            Task { @MainActor in
                guard await viewModel.verifyReferralEntries(tx: sendTx) else {
                    return
                }

                onNext()
            }
        }
        .disabled(!viewModel.isValidForm)
    }

    var alert: Alert {
        Alert(
            title: Text(NSLocalizedString("error", comment: "")),
            message: Text(NSLocalizedString(viewModel.errorMessage ?? .empty, comment: "")),
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
                .foregroundColor(Theme.colors.textPrimary)
        }
    }

    var infoLabel: some View {
        Image(systemName: "info.circle")
            .font(Theme.fonts.bodyLMedium)
            .foregroundColor(Theme.colors.textPrimary)
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
                .foregroundColor(Theme.colors.textTertiary)

            Spacer()

            VStack(alignment: .trailing, spacing: 0) {
                RedactedText(description1, redactedText: redactedDesc1, isLoading: isPlaceholder)
                    .foregroundColor(Theme.colors.textPrimary)

                if !description2.isEmpty {
                    RedactedText(description2, redactedText: redactedDesc2, isLoading: isPlaceholder)
                        .foregroundColor(Theme.colors.textTertiary)
                }
            }
        }
        .font(Theme.fonts.bodySMedium)
    }
}

#Preview {
    EditReferralDetailsView(
        viewModel: EditReferralViewModel(
            nativeCoin: .example,
            vault: .example,
            thornameDetails: .example,
            currentBlockHeight: 0
        ),
        sendTx: SendTransaction(),
        onNext: {}
    )
}
