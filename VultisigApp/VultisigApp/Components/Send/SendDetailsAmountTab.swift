//
//  SendDetailsAmountTab.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-07-02.
//

import SwiftUI
import VultisigUIResources

struct SendDetailsAmountTab: View {
    let isShown: Bool
    let transition: AnyTransition
    @Bindable var viewModel: SendDetailsViewModel
    let validateForm: () async -> Void
    @FocusState.Binding var focusedField: Field?
    @Binding var settingsPresented: Bool
    @State var percentage: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let feeEstimateDebounce: Duration = .milliseconds(500)
    private static let outdatedFeeOpacity: Double = 0.5
    private static let feeSkeletonCryptoSize = CGSize(width: 72, height: 12)
    private static let feeSkeletonFiatSize = CGSize(width: 44, height: 10)

    var body: some View {
        content
    }

    var content: some View {
        VStack(spacing: 0) {
            if isShown {
                fields
                    // Lives only while the step is shown, so leaving it cancels the estimate.
                    .task(id: viewModel.feeEstimateInputs) {
                        await estimateFeeAfterDebounce()
                    }
                    .transition(transition)
            }
        }
    }

    private func estimateFeeAfterDebounce() async {
        do {
            try await Task.sleep(for: Self.feeEstimateDebounce)
        } catch {
            return
        }
        await viewModel.estimateFee()
    }

    var fields: some View {
        VStack(spacing: 16) {
            chainHeader
            amountFieldSection

            errorText
                .transition(.verticalGrowAndFade)
                .animation(.interpolatingSpring, value: viewModel.showAmountAlert)
                .showIf(viewModel.showAmountAlert)

            amountWarningText(viewModel.amountValidation.message ?? .empty)
                .transition(.verticalGrowAndFade)
                .animation(.interpolatingSpring, value: viewModel.amountValidation.message)
                .showIf(viewModel.amountValidation.message != nil)

            percentageButtons
            balanceSection
            additionalOptionsSection
            Separator(color: Theme.colors.borderLight, opacity: 1)
            feeRow
        }
        .padding(16)
        .background(Theme.radius.xl.shape.fill(Theme.colors.bgSurface1))
        .overlay(Theme.radius.xl.shape.strokeBorder(Theme.colors.borderLight, lineWidth: 1))
    }

    var chainHeader: some View {
        HStack(spacing: 4) {
            VultisigImage(viewModel.coin.chain.logo)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
            Text(viewModel.coin.chain.displayName)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)
        }
    }

    /// Opens the fee settings sheet on chains that have one; elsewhere a plain label.
    @ViewBuilder
    var feeRow: some View {
        if viewModel.coin.supportsFeeSettings {
            Button {
                settingsPresented = true
            } label: {
                feeLabel(showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("estNetworkFee".localized)
            .accessibilityValue(viewModel.feeEstimate?.crypto ?? .empty)
        } else {
            feeLabel(showsChevron: false)
        }
    }

    func feeLabel(showsChevron: Bool) -> some View {
        HStack(spacing: 4) {
            Text("estNetworkFee".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
            if showsChevron {
                Icon(.chevronRightSmall, color: Theme.colors.textTertiary, size: 12)
            }
            Spacer()
            feeValue
        }
        .contentShape(Rectangle())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: viewModel.feeEstimate)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: viewModel.isEstimatingFee)
    }

    @ViewBuilder
    var feeValue: some View {
        if let estimate = viewModel.feeEstimate {
            VStack(alignment: .trailing, spacing: 2) {
                Text(estimate.crypto)
                    .font(Theme.fonts.priceFootnote)
                    .foregroundStyle(Theme.colors.textPrimary)
                if !estimate.fiat.isEmpty {
                    Text(estimate.fiat)
                        .font(Theme.fonts.priceCaption)
                        .foregroundStyle(Theme.colors.textTertiary)
                }
            }
            .opacity(viewModel.isFeeEstimateOutdated ? Self.outdatedFeeOpacity : 1)
            .transition(.opacity)
        } else if viewModel.isEstimatingFee {
            feeSkeleton
                .transition(.opacity)
        }
    }

    var feeSkeleton: some View {
        VStack(alignment: .trailing, spacing: 6) {
            skeletonBar(Self.feeSkeletonCryptoSize)
            skeletonBar(Self.feeSkeletonFiatSize)
        }
        .accessibilityHidden(true)
    }

    private func skeletonBar(_ size: CGSize) -> some View {
        Theme.radius.xs.shape
            .fill(Theme.colors.borderLight.opacity(0.3))
            .frame(width: size.width, height: size.height)
    }

    var amountFieldSection: some View {
        SendDetailsAmountTextField(viewModel: viewModel, focusedField: $focusedField)
            .id(Field.amount)
            .onSubmit {
                Task {
                    await validateForm()
                }
            }
    }

    @ViewBuilder
    var percentageButtons: some View {
        PercentageButtonsStack(selectedPercentage: $percentage)
            .onChange(of: percentage) { _, newValue in
                guard let newValue else { return }
                viewModel.setMaxAmount(percentage: newValue)
            }
    }

    var balanceSection: some View {
        HStack {
            Text(NSLocalizedString("balanceAvailable", comment: ""))
            Spacer()
            Text(viewModel.coin.balanceString + " " + viewModel.coin.ticker)
        }
        .font(Theme.fonts.bodySMedium)
        .foregroundStyle(Theme.colors.textPrimary)
        .padding(12)
        .padding(.vertical, 8)
        .background(Theme.colors.bgSurface12)
        .cornerRadius(Theme.radius.md)
    }

    var additionalOptionsSection: some View {
        SendDetailsAdditionalSection(viewModel: viewModel, focusedField: $focusedField)
    }

    var errorText: some View {
        Text(NSLocalizedString(viewModel.errorMessage ?? .empty, comment: ""))
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.alertWarning)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Inline early-feedback warning surfaced by the async amount validators
    // (e.g. a native XRP send below the destination's base reserve). The message
    // is already localized and formatted by the VM, so render it directly (not
    // via NSLocalizedString).
    func amountWarningText(_ message: String) -> some View {
        Text(message)
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.alertWarning)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
