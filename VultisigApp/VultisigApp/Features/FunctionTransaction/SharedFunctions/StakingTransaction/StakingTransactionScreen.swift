//
//  StakingTransactionScreen.swift
//  VultisigApp
//
//  One descriptor-driven screen for the validator-staking input forms (Cosmos
//  delegate/undelegate, Solana delegate/unstake/withdraw). It renders the shared
//  `FormScreen` scaffold plus, in order: an optional amount section, read-only
//  display rows, an optional validator picker, and the notices list — all from
//  the `StakingFormViewModel` specs.
//
//  The focus + percentage plumbing (previously copy-pasted, with a
//  `DispatchQueue.main.asyncAfter` focus hack, into every screen) lives here
//  ONCE, using a cancellable `Task` so a later focus change supersedes an
//  in-flight one. The validator-picker sheet is supplied by the caller because
//  it binds the chain-specific selection.
//

import SwiftUI

struct StakingTransactionScreen<VM: StakingFormViewModel, Sheet: View>: View {
    private enum Field: Hashable {
        case amount
    }

    @StateObject private var viewModel: VM
    let onVerify: (TransactionBuilder) -> Void
    @ViewBuilder let pickerSheet: (_ isPresented: Binding<Bool>, _ viewModel: VM) -> Sheet

    init(
        viewModel: VM,
        onVerify: @escaping (TransactionBuilder) -> Void,
        @ViewBuilder pickerSheet: @escaping (_ isPresented: Binding<Bool>, _ viewModel: VM) -> Sheet
    ) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.onVerify = onVerify
        self.pickerSheet = pickerSheet
    }

    @State private var focusedFieldBinding: Field?
    @FocusState private var focusedField: Field?
    @State private var percentageSelected: Double?
    @State private var showPicker: Bool = false
    @State private var focusTask: Task<Void, Never>?

    var body: some View {
        FormScreen(
            title: String(format: viewModel.titleKey.localized, viewModel.coin.ticker),
            validForm: $viewModel.validForm,
            isContinueDisabled: viewModel.isContinueDisabled,
            onContinue: onContinue
        ) {
            if let amount = viewModel.amountSpec {
                amountSection(amount)
            }

            ForEach(viewModel.readOnlyRows) { row in
                FormPickerSection(title: row.title, value: row.value, isValid: true, onTap: {})
                    .disabled(true)
            }

            if let picker = viewModel.pickerSpec {
                pickerSection(picker)
            }

            ForEach(viewModel.notices) { notice in
                noticeView(notice)
            }
        }
        .crossPlatformSheet(isPresented: $showPicker) {
            pickerSheet($showPicker, viewModel)
        }
        .onLoad {
            viewModel.onLoad()
            if viewModel.amountSpec != nil {
                focusedFieldBinding = .amount
            }
            if viewModel.amountSpec?.seedMaxOnLoad == true {
                percentageSelected = 100
            }
        }
        .onChange(of: percentageSelected) { _, newValue in
            guard let newValue else { return }
            viewModel.onPercentage(newValue)
        }
        .onChange(of: viewModel.pickerSpec?.selectionToken) { _, _ in
            // A validator was (re)selected — refocus the amount field on the
            // flows that have one, matching the per-screen behavior.
            guard viewModel.amountSpec != nil else { return }
            focusedFieldBinding = .amount
        }
        .onChange(of: focusedFieldBinding) { _, newValue in
            // Cancellable delay so a later focus change supersedes an in-flight
            // one instead of a stale callback refocusing the amount field.
            focusTask?.cancel()
            focusTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                focusedField = newValue
            }
        }
    }

    @ViewBuilder
    private func amountSection(_ spec: StakingAmountSpec) -> some View {
        FormExpandableSection(
            title: spec.field.label ?? .empty,
            isValid: spec.field.valid,
            value: .empty,
            showValue: false,
            focusedField: $focusedFieldBinding,
            focusedFieldEquals: .amount
        ) {
            focusedFieldBinding = $0 ? .amount : nil
        } content: {
            AmountTextField(
                amount: valueBinding(for: spec.field),
                error: errorBinding(for: spec.field),
                ticker: spec.ticker,
                type: spec.type,
                availableAmount: spec.availableAmount,
                decimals: spec.decimals,
                percentage: $percentageSelected
            )
            .focused($focusedField, equals: .amount)
        }
    }

    @ViewBuilder
    private func pickerSection(_ spec: StakingPickerSpec) -> some View {
        FormPickerSection(
            title: spec.title,
            isValid: spec.isSelected,
            onTap: { showPicker = true },
            valueView: { previewView(spec.preview) }
        )
    }

    @ViewBuilder
    private func previewView(_ preview: StakingValidatorPreview?) -> some View {
        if let preview {
            HStack(spacing: 8) {
                if let avatar = preview.avatar {
                    StakingValidatorAvatar(avatar: avatar, size: 20)
                }
                Text(preview.name)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func noticeView(_ notice: StakingNotice) -> some View {
        switch notice {
        case .info(let message):
            InfoBannerView(description: message, type: .info, leadingIcon: "circle-info")
        case .insufficientFee(let ticker):
            InsufficientFeeNotice(ticker: ticker)
        }
    }

    private func onContinue() {
        if let picker = viewModel.pickerSpec, !picker.isSelected {
            showPicker = true
            return
        }
        guard let transactionBuilder = viewModel.transactionBuilder else { return }
        onVerify(transactionBuilder)
    }

    private func valueBinding(for field: FormField) -> Binding<String> {
        Binding(get: { field.value }, set: { field.value = $0 })
    }

    private func errorBinding(for field: FormField) -> Binding<String?> {
        Binding(get: { field.error }, set: { field.error = $0 })
    }
}
