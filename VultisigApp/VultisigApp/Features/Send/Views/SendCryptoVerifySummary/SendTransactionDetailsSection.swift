//
//  SendTransactionDetailsSection.swift
//  VultisigApp
//

import SwiftUI

/// The decoded contract call behind a transaction: its function signature and
/// arguments, folded away until asked for.
struct SendTransactionDetailsSection: View {
    let input: SendCryptoVerifySummary
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center) {
                    Text("transactionDetails".localized)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textTertiary)
                    Spacer()
                    Icon(.chevronDown, color: Theme.colors.textTertiary, size: 16)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.borderless)

            if isExpanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let signature = input.decodedFunctionSignature, !signature.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("functionSignature".localized)
                                    .foregroundStyle(Theme.colors.textTertiary)
                                    .font(Theme.fonts.bodySMedium)

                                Text(signature)
                                    .foregroundStyle(Theme.colors.turquoise)
                                    .font(Theme.fonts.bodySMedium)
                                    .textSelection(.enabled)
                            }
                        }

                        if let args = input.decodedFunctionArguments, !args.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("functionArguments".localized)
                                    .foregroundStyle(Theme.colors.textTertiary)
                                    .font(Theme.fonts.bodySMedium)

                                Text(args)
                                    .foregroundStyle(Theme.colors.turquoise)
                                    .font(Theme.fonts.bodySMedium)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
                .frame(maxHeight: 300)
                .background(Theme.radius.lg.shape.fill(Theme.colors.bgSurface2))
            }
        }
    }
}
