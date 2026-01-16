//
//  SettingsCommonOptionView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/08/2025.
//

import SwiftUI

enum SettingsOptionViewType {
    case normal
    case highlighted
    case alert
}

struct SettingsOptionView<TrailingView: View>: View {
    let icon: String?
    let title: String
    let subtitle: String?
    let type: SettingsOptionViewType
    let showSeparator: Bool
    let trailingView: () -> TrailingView
    
    init(
        icon: String?,
        title: String,
        subtitle: String? = nil,
        type: SettingsOptionViewType = .normal,
        showSeparator: Bool = true,
        @ViewBuilder trailingView: @escaping () -> TrailingView
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.type = type
        self.showSeparator = showSeparator
        self.trailingView = trailingView
    }
    
    var bgColor: Color? {
        switch type {
        case .normal, .alert:
            return nil
        case .highlighted:
            return Theme.colors.primaryAccent3
        }
    }
    
    var iconColor: Color {
        switch type {
        case .normal:
            return Theme.colors.primaryAccent4
        case .highlighted:
            return Theme.colors.textPrimary
        case .alert:
            return Theme.colors.alertError
        }
    }
    
    var fontColor: Color {
        switch type {
        case .normal, .highlighted:
            return Theme.colors.textPrimary
        case .alert:
            return Theme.colors.alertError
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let icon {
                    Icon(named: icon, color: iconColor, size: 20)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title.localized)
                        .font(Theme.fonts.footnote)
                        .foregroundStyle(fontColor)
                    
                    if let subtitle {
                        Text(subtitle)
                            .font(Theme.fonts.caption12)
                            .foregroundStyle(fontColor)
                            .multilineTextAlignment(.leading)
                    }
                }
                
                Spacer()
                
                trailingView()
                    .foregroundStyle(fontColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
            .background(bgColor)
            GradientListSeparator()
                .showIf(showSeparator)
        }
    }
}
