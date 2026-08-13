//
//  FormLoadFailureNote.swift
//  VultisigApp
//

import SwiftUI

/// Says why a form cannot be completed when the data it needs never arrived.
///
/// These forms fail closed: no assets means no selected asset, which means
/// `transactionBuilder` returns nil, which means Continue does nothing. Without
/// this note the screen looks merely unresponsive, and the user has no way to
/// tell a network failure from holding nothing bondable.
struct FormLoadFailureNote: View {
    /// Localization key for the explanation.
    let messageKey: String
    /// Omitted when there is nothing a retry could change.
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            InformationNote(message: messageKey.localized)

            if let onRetry {
                PrimaryButton(title: "retry", type: .secondary, size: .small, action: onRetry)
            }
        }
    }
}

#Preview {
    ZStack {
        Background()
        FormLoadFailureNote(messageKey: "bondableAssetsLoadFailed") {}
            .padding(16)
    }
}
