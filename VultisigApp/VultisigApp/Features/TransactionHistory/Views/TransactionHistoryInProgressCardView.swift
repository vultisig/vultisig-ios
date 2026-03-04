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
            fromRow
            arrowDown
            toSeparator
            arrowDown
            toRow
        }
        .padding(16)
        .padding(.bottom, transaction.swapProvider != nil ? 20 : 0)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) {
            viaBadge
        }
        .onAppear { startTimer() }
        .onDisappear { stopTimer() }
    }

    // MARK: - Top Row

    private var topRow: some View {
        HStack(alignment: .top) {
            TransactionHistoryTypePill(type: transaction.type)

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Text("inProgress".localized + "...")
                        .font(Theme.fonts.caption10)
                        .foregroundStyle(Theme.colors.textTertiary)
                    Text(elapsedTimeString)
                        .font(Theme.fonts.caption10)
                        .foregroundStyle(Theme.colors.textTertiary)
                }

                progressBar
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.colors.border)
                    .frame(height: 3)

                Capsule()
                    .fill(Theme.colors.primaryAccent4)
                    .frame(width: geometry.size.width * progressWidth, height: 3)
                    .animation(.linear(duration: 1), value: elapsedTime)
            }
        }
        .frame(width: 120, height: 3)
    }

    private var progressWidth: CGFloat {
        guard let estimatedSeconds = transaction.estimatedTime.flatMap({ parseEstimatedSeconds($0) }),
              estimatedSeconds > 0 else {
            let pulse = (sin(elapsedTime * 0.5) + 1) / 2
            return 0.3 + pulse * 0.4
        }
        return min(elapsedTime / estimatedSeconds, 0.95)
    }

    private func parseEstimatedSeconds(_ text: String) -> TimeInterval? {
        let numbers = text.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap(Double.init)
        guard let value = numbers.last else { return nil }

        if text.contains("min") {
            return value * 60
        }
        return value
    }

    // MARK: - From Row

    private var fromRow: some View {
        HStack(spacing: 8) {
            AsyncImageView(
                logo: transaction.coinLogo,
                size: CGSize(width: 24, height: 24),
                ticker: transaction.coinTicker,
                tokenChainLogo: transaction.coinChainLogo
            )

            cryptoAmountText(transaction.amountCrypto, ticker: transaction.coinTicker)
        }
    }

    // MARK: - Arrow Down

    private var arrowDown: some View {
        Image(systemName: "arrow.down")
            .font(.system(size: 12))
            .foregroundStyle(Theme.colors.textTertiary)
            .padding(.leading, 6)
    }

    // MARK: - To Separator

    private var toSeparator: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle")
                .font(.system(size: 16))
                .foregroundStyle(Theme.colors.textTertiary)

            Text("to".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)

            dashedLine
        }
    }

    private var dashedLine: some View {
        GeometryReader { geometry in
            Path { path in
                path.move(to: CGPoint(x: 0, y: 1.5))
                path.addLine(to: CGPoint(x: geometry.size.width, y: 1.5))
            }
            .stroke(
                Theme.colors.border,
                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
            )
        }
        .frame(height: 3)
    }

    // MARK: - To Row

    @ViewBuilder
    private var toRow: some View {
        if transaction.type == .swap {
            swapToRow
        } else {
            sendToRow
        }
    }

    private var swapToRow: some View {
        HStack(spacing: 8) {
            if let toCoinLogo = transaction.toCoinLogo {
                AsyncImageView(
                    logo: toCoinLogo,
                    size: CGSize(width: 24, height: 24),
                    ticker: transaction.toCoinTicker ?? "",
                    tokenChainLogo: transaction.toCoinChainLogo
                )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("minPayout".localized)
                    .font(Theme.fonts.caption10)
                    .foregroundStyle(Theme.colors.textTertiary)

                cryptoAmountText(transaction.toAmountCrypto ?? "", ticker: transaction.toCoinTicker ?? "")
            }
        }
    }

    private var sendToRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 16))
                .foregroundStyle(Theme.colors.textTertiary)
                .frame(width: 24, height: 24)

            Text(truncatedAddress(transaction.toAddress))
                .font(Theme.fonts.priceFootnote)
                .foregroundStyle(Theme.colors.textPrimary)
                .lineLimit(1)
        }
    }

    // MARK: - Via Badge

    @ViewBuilder
    private var viaBadge: some View {
        if let provider = transaction.swapProvider {
            HStack(spacing: 6) {
                providerIcons

                HStack(spacing: 4) {
                    Text("via".localized)
                        .foregroundStyle(Theme.colors.textTertiary)
                    Text(provider)
                        .foregroundStyle(Theme.colors.textPrimary)
                }
                .font(Theme.fonts.caption10)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.colors.bgSurface2)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 12,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 16,
                    topTrailingRadius: 0
                )
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 12,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 16,
                    topTrailingRadius: 0
                )
                .stroke(Theme.colors.border, lineWidth: 1)
            )
        }
    }

    private var providerIcons: some View {
        ZStack {
            if let toCoinLogo = transaction.toCoinLogo {
                AsyncImageView(
                    logo: toCoinLogo,
                    size: CGSize(width: 16, height: 16),
                    ticker: transaction.toCoinTicker ?? "",
                    tokenChainLogo: nil
                )
                .offset(x: 6)
            }

            AsyncImageView(
                logo: transaction.coinLogo,
                size: CGSize(width: 16, height: 16),
                ticker: transaction.coinTicker,
                tokenChainLogo: nil
            )
            .offset(x: -6)
        }
        .frame(width: 28, height: 16)
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

    // MARK: - Helpers

    private func cryptoAmountText(_ crypto: String, ticker: String) -> some View {
        let amount = crypto.hasSuffix(ticker)
            ? String(crypto.dropLast(ticker.count)).trimmingCharacters(in: .whitespaces)
            : crypto

        return HStack(spacing: 4) {
            Text(amount)
                .foregroundStyle(Theme.colors.textPrimary)
            Text(ticker)
                .foregroundStyle(Theme.colors.textTertiary)
        }
        .font(Theme.fonts.priceFootnote)
        .lineLimit(1)
    }

    private func truncatedAddress(_ address: String) -> String {
        guard address.count > 10 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }
}
