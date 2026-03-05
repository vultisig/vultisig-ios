//
//  TransactionHistoryTypePill.swift
//  VultisigApp
//

import SwiftUI

struct TransactionHistoryTypePill: View {
    let type: TransactionHistoryType

    var body: some View {
        HStack(spacing: 4) {
            iconView
            Text(title)
                .font(Theme.fonts.caption12)
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(foregroundColor.opacity(0.1))
        .cornerRadius(99)
        .overlay(
            RoundedRectangle(cornerRadius: 99)
                .stroke(foregroundColor, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var iconView: some View {
        switch type {
        case .send:
            Image("send")
                .resizable()
                .frame(width: 12, height: 12)
        case .swap:
            Image("arrow-rotate-left-right")
                .resizable()
                .frame(width: 12, height: 12)
        case .approve:
            Image(systemName: "checkmark.shield")
                .font(.system(size: 10))
        }
    }

    private var title: String {
        switch type {
        case .send:
            return "send".localized
        case .swap:
            return "swap".localized
        case .approve:
            return "approve".localized
        }
    }

    private var foregroundColor: Color {
        Theme.colors.alertInfo
    }
}
