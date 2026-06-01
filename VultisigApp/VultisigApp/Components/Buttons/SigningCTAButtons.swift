//
//  SigningCTAButtons.swift
//  VultisigApp
//

import SwiftUI

/// Bottom call-to-action row for fast/paired signing confirmation screens.
///
/// Fast Vaults render two side-by-side buttons: a primary, flexible-width
/// "Fast Sign" (server co-sign via the FastVault password sheet) and a
/// fixed-width secondary "Paired" button (paired-device signing). Secure
/// (N-of-M) vaults render a single full-width button that triggers the
/// paired path.
struct SigningCTAButtons: View {
    let isFastVault: Bool
    let isLoading: Bool
    let isDisabled: Bool
    /// Title used for the single full-width button shown to secure vaults.
    let singleSignTitle: String
    let onFastSign: () -> Void
    let onPairedSign: () -> Void

    init(
        isFastVault: Bool,
        isLoading: Bool = false,
        isDisabled: Bool = false,
        singleSignTitle: String = "sign",
        onFastSign: @escaping () -> Void,
        onPairedSign: @escaping () -> Void
    ) {
        self.isFastVault = isFastVault
        self.isLoading = isLoading
        self.isDisabled = isDisabled
        self.singleSignTitle = singleSignTitle
        self.onFastSign = onFastSign
        self.onPairedSign = onPairedSign
    }

    var body: some View {
        Group {
            if isFastVault {
                fastVaultButtons
            } else {
                singleSignButton
            }
        }
        .disabled(isDisabled)
    }

    private var fastVaultButtons: some View {
        HStack(spacing: 12) {
            PrimaryButton(
                title: "fastSign".localized,
                isLoading: isLoading,
                type: .primary,
                size: .medium,
                action: onFastSign
            )
            .frame(maxWidth: .infinity)

            PrimaryButton(
                title: "paired".localized,
                leadingView: {
                    Icon(named: "devices", color: Theme.colors.textPrimary, size: 20)
                },
                type: .secondary,
                size: .medium,
                action: onPairedSign
            )
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var singleSignButton: some View {
        PrimaryButton(
            title: singleSignTitle.localized,
            isLoading: isLoading,
            type: .primary,
            size: .medium,
            action: onPairedSign
        )
    }
}

#Preview {
    VStack(spacing: 24) {
        SigningCTAButtons(isFastVault: true) {} onPairedSign: {}
        SigningCTAButtons(isFastVault: true, isLoading: true) {} onPairedSign: {}
        SigningCTAButtons(isFastVault: true, isDisabled: true) {} onPairedSign: {}
        SigningCTAButtons(isFastVault: false) {} onPairedSign: {}
    }
    .padding(16)
}
