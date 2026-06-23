//
//  ExternalRecipientSettingsView.swift
//  VultisigApp
//
//  External Recipient sub-sheet: a "Send to Different Address" input with the
//  existing paste / QR-scan / address-book accessory actions. The entry is
//  resolved (ENS `.eth` for EVM, THORName/TNS for THORChain/Maya, …) and
//  validated for the destination chain by `ExternalRecipientViewModel` before
//  the RESOLVED address is persisted; an empty field clears the recipient (swap
//  to the user's own address). Resolution/validation live in the view model.
//

import SwiftUI

struct ExternalRecipientSettingsView: View {
    let coin: Coin
    @Binding var recipient: String?
    let onBack: () -> Void

    @State private var viewModel: ExternalRecipientViewModel

    init(coin: Coin, recipient: Binding<String?>, onBack: @escaping () -> Void) {
        self.coin = coin
        self._recipient = recipient
        self.onBack = onBack
        self._viewModel = State(
            initialValue: ExternalRecipientViewModel(chain: coin.chain, initialRecipient: recipient.wrappedValue)
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            AdvancedSwapSheetHeader(title: "useExternalRecipient".localized, showBack: true, onClose: onBack)

            AddressTextField(
                address: addressBinding,
                label: "sendToDifferentAddress".localized,
                coin: coin,
                error: errorBinding,
                onAddressResult: handle
            )
            .padding(.horizontal, 16)

            if viewModel.isResolving {
                resolvingLabel
            } else if let name = viewModel.resolvedNameLabel {
                resolvedLabel(name: name)
            }

            Spacer(minLength: 0)
        }
        .onLoad {
            resolveAndPersist()
        }
        .onChange(of: viewModel.input) { _, _ in
            resolveAndPersist()
        }
        .onDisappear {
            viewModel.cancel()
        }
    }

    private var resolvingLabel: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("resolvingRecipientName".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private func resolvedLabel(name: String) -> some View {
        HStack(spacing: 8) {
            Text(name)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    /// Bridges the form field's value to the `AddressTextField` text binding so
    /// edits flow through the view model's resolve + validate path.
    private var addressBinding: Binding<String> {
        Binding(
            get: { viewModel.input },
            set: { viewModel.input = $0 }
        )
    }

    /// Read-only bridge of the form-layer error to the text field. The form owns
    /// the error; the text field never writes it.
    private var errorBinding: Binding<String?> {
        Binding(
            get: { viewModel.error },
            set: { _ in }
        )
    }

    private func handle(_ result: AddressResult?) {
        guard let result else { return }
        viewModel.apply(address: result.address)
    }

    private func resolveAndPersist() {
        viewModel.resolveAndPersist { resolved in
            recipient = resolved
        }
    }
}

#Preview {
    struct PreviewContainer: View {
        @State var recipient: String?
        var body: some View {
            ExternalRecipientSettingsView(coin: .example, recipient: $recipient) {}
                .background(Theme.colors.bgPrimary)
        }
    }
    return PreviewContainer()
}
