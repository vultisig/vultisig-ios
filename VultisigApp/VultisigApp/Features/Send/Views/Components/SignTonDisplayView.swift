//
//  SignTonDisplayView.swift
//  VultisigApp
//
//  Component to display TonConnect multi-message transaction data
//

import SwiftUI

struct SignTonDisplayView: View {
    let signTon: SignTon
    let coinTicker: String
    let coinDecimals: Int

    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center) {
                    Text("tonConnectMessages".localized)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textTertiary)
                    Spacer()
                    Text("\(signTon.tonMessages.count)")
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textTertiary)
                    Icon(named: "chevron-down", color: Theme.colors.textTertiary, size: 16)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.borderless)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(signTon.tonMessages.enumerated()), id: \.offset) { index, message in
                        messageRow(index: index, message: message)
                    }
                }
            }
        }
    }

    private func messageRow(index: Int, message: TonMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("#\(index + 1)")
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                Spacer()
                Text("\(formatAmount(message.amount)) \(coinTicker)")
                    .font(Theme.fonts.priceBodyS)
                    .foregroundStyle(Theme.colors.textPrimary)
            }

            Text(message.to)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)

            if message.stateInit != nil || message.payload != nil {
                HStack(spacing: 6) {
                    if message.stateInit != nil {
                        badge("tonConnectStateInitBadge".localized)
                    }
                    if message.payload != nil {
                        badge("tonConnectPayloadBadge".localized)
                    }
                    Spacer()
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.colors.bgPrimary)
        .cornerRadius(8)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(Theme.fonts.caption10)
            .foregroundStyle(Theme.colors.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.colors.bgSurface2)
            .cornerRadius(4)
    }

    private func formatAmount(_ raw: String) -> String {
        guard let value = Decimal(string: raw) else { return raw }
        let power = Decimal(sign: .plus, exponent: -coinDecimals, significand: 1)
        return (value * power).formatForDisplay()
    }
}
