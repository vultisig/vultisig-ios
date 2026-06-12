//
//  ExternalRecipientSettingsView.swift
//  VultisigApp
//
//  External Recipient sub-sheet: a "Send to Different Address" input with the
//  existing paste / QR-scan / address-book accessory actions. The entered
//  address is validated for the destination chain before it's persisted; an
//  empty field clears the recipient (swap to the user's own address).
//

import SwiftUI

struct ExternalRecipientSettingsView: View {
    let coin: Coin
    @Binding var recipient: String?
    let onBack: () -> Void

    @State private var address: String = .empty
    @State private var error: String?

    var body: some View {
        VStack(spacing: 12) {
            AdvancedSwapSheetHeader(title: "useExternalRecipient".localized, showBack: true, onClose: onBack)

            AddressTextField(
                address: $address,
                label: "sendToDifferentAddress".localized,
                coin: coin,
                error: $error,
                onAddressResult: handle
            )
            .padding(.horizontal, 16)

            Spacer(minLength: 0)
        }
        .onLoad {
            address = recipient ?? .empty
            validateAndPersist()
        }
        .onChange(of: address) { _, _ in
            validateAndPersist()
        }
    }

    private func handle(_ result: AddressResult?) {
        guard let result else { return }
        address = result.address
    }

    /// Validate the entered address for the coin's chain and persist it. An empty
    /// field clears the recipient (own-address swap); an invalid address surfaces
    /// an inline error and is NOT persisted, so an invalid recipient can never
    /// reach signing.
    private func validateAndPersist() {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            recipient = nil
            error = nil
            return
        }
        if AddressService.validateAddress(address: trimmed, chain: coin.chain) {
            recipient = trimmed
            error = nil
        } else {
            recipient = nil
            error = "validAddressError".localized
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
