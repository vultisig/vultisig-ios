//
//  SendDetailsAmountTab.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-07-02.
//

import SwiftUI

struct SendDetailsAmountTab: View {
    let isExpanded: Bool
    @Bindable var viewModel: SendDetailsViewModel
    let validateForm: () async -> Void
    @FocusState.Binding var focusedField: Field?
    @Binding var settingsPresented: Bool
    @State var percentage: Double?

    var body: some View {
        content
            .padding(.bottom, 65)
            .clipped()
            .onChange(of: isExpanded) { _, newValue in
                guard newValue else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    focusedField = .amount
                }
            }
    }

    var content: some View {
        SendFormExpandableSection(
            isExpanded: isExpanded,
            cornerRadius: 24,
            horizontalPadding: 16,
            verticalPadding: 20,
            backgroundColor: Theme.colors.bgPrimary
        ) {
            titleSection
        } content: {
            VStack(spacing: 16) {
                separator
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
            }
        }
    }

    var titleSection: some View {
        HStack {
            Text(NSLocalizedString("amount", comment: ""))
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)

            Spacer()

            if showGasSelector {
                gasSelector
            }
        }
        .background(Background().opacity(0.01))
        .onTapGesture {
            viewModel.onSelect(tab: .amount)
        }
    }

    var separator: some View {
        Separator(color: Theme.colors.borderLight, opacity: 1)
    }

    var showGasSelector: Bool {
        isExpanded && viewModel.coin.supportsFeeSettings
    }

    var gasSelector: some View {
        Button {
            settingsPresented.toggle()
        } label: {
            editLabel
        }
    }

    var editLabel: some View {
        Image(systemName: "fuelpump")
            .foregroundStyle(Theme.colors.textPrimary)
            .font(Theme.fonts.bodyMMedium)
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
        .background(Theme.colors.bgSurface1)
        .cornerRadius(12)
    }

    var additionalOptionsSection: some View {
        SendDetailsAdditionalSection(viewModel: viewModel)
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
