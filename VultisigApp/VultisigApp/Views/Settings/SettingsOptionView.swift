//
//  SettingsOptionView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/08/2025.
//

import SwiftUI

struct SettingsOptionView: View {
    enum OptionType {
        case normal
        case highlighted
        case alert
    }
    
    let icon: String?
    let title: String
    let subtitle: String?
    let description: String?
    let type: OptionType
    let showSeparator: Bool
    
    init(
        icon: String?,
        title: String,
        subtitle: String? = nil,
        description: String? = nil,
        type: OptionType = .normal,
        showSeparator: Bool = true
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.description = description
        self.type = type
        self.showSeparator = showSeparator
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
                    }
                }
                
                Spacer()
                
                if let description {
                    Text(description)
                        .font(Theme.fonts.footnote)
                        .foregroundStyle(fontColor)
                }
                
                Icon(
                    named: "chevron-right",
                    color: Theme.colors.textExtraLight,
                    size: 16
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
            .background(bgColor)
            GradientListSeparator()
                .showIf(showSeparator)
        }
    }
}
