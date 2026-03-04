//
//  TransactionHistoryTypePill.swift
//  VultisigApp
//

import SwiftUI

struct TransactionHistoryTypePill: View {
    let type: TransactionHistoryType

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 10))
            Text(title)
                .font(Theme.fonts.caption10)
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(foregroundColor.opacity(0.1))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(foregroundColor.opacity(0.3), lineWidth: 1)
        )
    }

    private var iconName: String {
        switch type {
        case .send:
            return "arrow.up.right"
        case .swap:
            return "arrow.left.arrow.right"
        case .approve:
            return "checkmark.shield"
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
