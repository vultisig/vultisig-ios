//
//  DydxVoteTransactionScreen.swift
//  VultisigApp
//
//  dYdX governance vote confirmation: the ballot option in one section, the
//  proposal ID in the next. The ballot list is inline rather than behind a
//  sheet — there are four fixed options and no search, filter or network read
//  a picker screen would justify.
//
//  Continue is deliberately not gated on `validForm` (see `FormScreen`);
//  `viewModel.transactionBuilder` returning nil is the enforcement, and the
//  tap is what reveals the errors on a form the user has not touched. Both
//  sections therefore observe their `FormField` directly, so the error a tap
//  produces is drawn in that same pass.
//

import SwiftUI
import WalletCore

/// Which section is open. Only the proposal ID has a real text field; the
/// ballot list uses the same value to drive expansion.
enum DydxVoteFocusedField: Hashable {
    case option
    case proposalID
}

struct DydxVoteTransactionScreen: View {
    @StateObject var viewModel: DydxVoteTransactionViewModel
    var onVerify: (TransactionBuilder) -> Void

    @State private var focusedFieldBinding: DydxVoteFocusedField?
    @FocusState private var focusedField: DydxVoteFocusedField?

    var body: some View {
        FormScreen(
            title: "Vote".localized,
            onContinue: onContinue
        ) {
            DydxVoteOptionSection(
                field: viewModel.optionField,
                options: viewModel.options,
                focusedField: $focusedFieldBinding,
                onSelect: select
            )

            DydxVoteProposalIDSection(
                field: viewModel.proposalIDField,
                focusedField: $focusedFieldBinding,
                textFieldFocus: $focusedField
            )
        }
        .onLoad {
            viewModel.onLoad()
            focusedFieldBinding = .option
        }
        .delayedFocus(from: focusedFieldBinding, to: $focusedField)
    }

    /// Picking a ballot option advances to the proposal ID, which is the only
    /// thing left to fill in.
    private func select(_ option: TW_Cosmos_Proto_Message.VoteOption) {
        viewModel.select(option)
        focusedFieldBinding = .proposalID
    }

    private func onContinue() {
        guard let transactionBuilder = viewModel.transactionBuilder else { return }
        onVerify(transactionBuilder)
    }
}

/// The ballot. Observes its `FormField` for two reasons: the "select an option"
/// error a Continue tap produces is drawn without waiting for the form
/// aggregate to republish a run-loop turn later, and the checked row is read
/// from the same field the memo is built from — one source, so the ballot shown
/// cannot differ from the ballot signed.
private struct DydxVoteOptionSection: View {
    @ObservedObject var field: FormField
    let options: [TW_Cosmos_Proto_Message.VoteOption]
    @Binding var focusedField: DydxVoteFocusedField?
    let onSelect: (TW_Cosmos_Proto_Message.VoteOption) -> Void

    private var selectedOption: TW_Cosmos_Proto_Message.VoteOption? {
        DydxVoteOption.option(forMemoValue: field.rawValue)
    }

    private var selectedTitle: String {
        guard let selectedOption else { return .empty }
        return DydxVoteOption.displayTitle(for: selectedOption)
    }

    var body: some View {
        FormExpandableSection(
            title: field.label ?? .empty,
            isValid: field.valid,
            value: selectedTitle,
            showValue: true,
            focusedField: $focusedField,
            focusedFieldEquals: .option
        ) {
            focusedField = $0 ? .option : nil
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(options, id: \.rawValue) { option in
                    row(for: option)
                }

                if let error = field.error {
                    Text(error.localized)
                        .font(Theme.fonts.footnote)
                        .foregroundStyle(Theme.colors.alertError)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func row(for option: TW_Cosmos_Proto_Message.VoteOption) -> some View {
        let isSelected = option == selectedOption
        return Button {
            onSelect(option)
        } label: {
            HStack(spacing: 8) {
                Text(DydxVoteOption.displayTitle(for: option))
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                Spacer()
                Icon(.check, color: Theme.colors.primaryAccent4, size: 16)
                    .showIf(isSelected)
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .frame(maxWidth: .infinity)
            .background(Theme.colors.bgSurface1)
            .cornerRadius(Theme.radius.md)
            .overlay(
                Theme.radius.md.shape
                    .stroke(
                        isSelected ? Theme.colors.primaryAccent4 : Theme.colors.border,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The proposal ID. Observes its `FormField` for the same reason the ballot
/// section does.
private struct DydxVoteProposalIDSection: View {
    @ObservedObject var field: FormField
    @Binding var focusedField: DydxVoteFocusedField?
    @FocusState.Binding var textFieldFocus: DydxVoteFocusedField?

    var body: some View {
        FormExpandableSection(
            title: field.label ?? .empty,
            isValid: field.valid,
            value: field.value,
            showValue: true,
            focusedField: $focusedField,
            focusedFieldEquals: .proposalID
        ) {
            focusedField = $0 ? .proposalID : nil
        } content: {
            textField
        }
    }

    /// `keyboardType` is iOS-only, so it is applied behind a platform guard;
    /// macOS uses the bare field.
    @ViewBuilder
    private var textField: some View {
        let common = CommonTextField(
            text: $field.value,
            placeholder: field.placeholder,
            error: $field.error
        )
        .focused($textFieldFocus, equals: .proposalID)

        #if os(iOS)
        common.keyboardType(.numberPad)
        #else
        common
        #endif
    }
}

#Preview {
    DydxVoteTransactionScreen(
        viewModel: DydxVoteTransactionViewModel(
            coin: .example,
            vault: .example
        )
    ) { _ in }
}
