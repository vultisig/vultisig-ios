//
//  TransactionStatusHeaderView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 26/01/2026.
//

import SwiftUI
import RiveRuntime

struct TransactionStatusHeaderView: View {
    let status: TransactionStatus
    @State private var pulseScale: CGFloat = 1.0
    @State private var successAnimationVM: RiveViewModel?
    @State private var errorAnimationVM: RiveViewModel?
    @State private var pendingAnimationVM: RiveViewModel?

    var body: some View {
        VStack(spacing: 0) {
            statusIndicator

            VStack(spacing: 12) {
                statusText
                statusDescription
            }
        }
        .animation(.interpolatingSpring, value: status)
        .onLoad {
            // TODO: - To be updated with state based animations
            pendingAnimationVM = RiveViewModel(fileName: "transaction_pending", autoPlay: false)
            pendingAnimationVM?.fit = .contain
            successAnimationVM = RiveViewModel(fileName: "vaultCreatedAnimation", autoPlay: false)
            successAnimationVM?.fit = .contain
            errorAnimationVM = RiveViewModel(fileName: "vaultCreatedAnimation", autoPlay: false)
            errorAnimationVM?.fit = .contain
        }
    }

    @ViewBuilder
    var statusIndicator: some View {
        VStack {
            Group {
                switch status {
                case .broadcasted, .pending:
                    if let pendingAnimationVM {
                        pendingAnimationVM.view()
                            .onAppear {
                                pendingAnimationVM.play()
                            }
                    }
                case .confirmed:
                    if let successAnimationVM {
                        successAnimationVM.view()
                            .onAppear {
                                successAnimationVM.play()
                            }
                    }
                case .failed, .timeout:
                    if let errorAnimationVM {
                        errorAnimationVM.view()
                            .onAppear {
                                errorAnimationVM.play()
                            }
                    }
                }
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var statusText: some View {
        Group {
            switch status {
            case .broadcasted:
                Text("transactionBroadcasted")
                    .foregroundStyle(Theme.colors.textPrimary)
                    .font(Theme.fonts.bodyLMedium)
            case .pending:
                Text("transactionPending")
                    .foregroundStyle(Theme.colors.textPrimary)
                    .font(Theme.fonts.bodyLMedium)
            case .confirmed:
                CustomHighlightText(
                    "transactionSuccessful".localized,
                    highlight: "transactionSuccessfulHighlight".localized,
                    style: LinearGradient.primaryGradientHorizontal
                )
                .foregroundStyle(Theme.colors.textPrimary)
                .font(Theme.fonts.bodyLMedium)
            case .timeout, .failed:
                HighlightedText(
                    text: "transactionFailed".localized,
                    highlightedText: "transactionFailedHighlight".localized
                ) { text in
                    text.foregroundColor = Theme.colors.textPrimary
                    text.font = Theme.fonts.bodyLMedium
                } highlightedTextStyle: { text in
                    text.foregroundColor = Theme.colors.alertError
                }
            }
        }
        .multilineTextAlignment(.center)
        .transition(.opacity)
    }

    @ViewBuilder
    var statusDescription: some View {
        if case let .failed(reason) = status {
            Text(reason)
                .foregroundStyle(Theme.colors.textTertiary)
                .font(Theme.fonts.bodySMedium)
                .multilineTextAlignment(.center)
        }
    }

    var pulsingCircle: some View {
        ZStack {
            Circle()
                .fill(Theme.colors.turquoise.opacity(0.3))
                .frame(width: 32, height: 32)
                .scaleEffect(pulseScale)
                .animation(
                    .easeInOut(duration: 1.5)
                    .repeatForever(autoreverses: true),
                    value: pulseScale
                )

            Circle()
                .fill(Theme.colors.turquoise)
                .frame(width: 16, height: 16)
        }
    }

}

#Preview {
    Screen {
        TransactionStatusHeaderView(status: .confirmed)
    }
}
