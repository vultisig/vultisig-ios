//
//  TransactionHistoryInProgressCardView.swift
//  VultisigApp
//

import SwiftUI

struct TransactionHistoryInProgressCardView: View {
    let transaction: TransactionHistoryData

    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            topRow
            progressSection
            detailSection
        }
        .padding(16)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
        .onAppear { startTimer() }
        .onDisappear { stopTimer() }
    }

    // MARK: - Top Row

    private var topRow: some View {
        HStack {
            TransactionHistoryTypePill(type: transaction.type)

            Spacer()

            HStack(spacing: 4) {
                Text("inProgress".localized)
                    .font(Theme.fonts.caption10)
                    .foregroundStyle(Theme.colors.textTertiary)
                Text(elapsedTimeString)
                    .font(Theme.fonts.caption10)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
        }
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        ProgressView()
            .progressViewStyle(LinearProgressViewStyle())
            .tint(Theme.colors.primaryAccent4)
    }

    // MARK: - Detail Section

    private var detailSection: some View {
        HStack(spacing: 12) {
            AsyncImageView(
                logo: transaction.coinLogo,
                size: CGSize(width: 36, height: 36),
                ticker: transaction.coinTicker,
                tokenChainLogo: transaction.coinChainLogo
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.amountCrypto)
                    .font(Theme.fonts.priceBodyS)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .lineLimit(1)

                if transaction.type == .swap, let toCoinTicker = transaction.toCoinTicker {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.colors.textTertiary)
                        Text(toCoinTicker)
                            .font(Theme.fonts.caption10)
                            .foregroundStyle(Theme.colors.textTertiary)
                    }
                }
            }

            Spacer()

            if let provider = transaction.swapProvider {
                Text("via".localized + " " + provider)
                    .font(Theme.fonts.caption10)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
        }
    }

    // MARK: - Timer

    private var elapsedTimeString: String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        return "\(minutes)m \(seconds)s"
    }

    private func startTimer() {
        elapsedTime = Date().timeIntervalSince(transaction.createdAt)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsedTime = Date().timeIntervalSince(transaction.createdAt)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
