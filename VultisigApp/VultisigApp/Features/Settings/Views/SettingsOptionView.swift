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

struct SettingsOptionView<TitleAccessory: View, TrailingView: View>: View {
    let icon: ImageResource?
    let title: String
    let subtitle: String?
    let type: SettingsOptionViewType
    let titleStyle: SettingsTextStyle
    let titleAccessory: () -> TitleAccessory
    let trailingView: () -> TrailingView

    init(
        icon: ImageResource?,
        title: String,
        subtitle: String? = nil,
        type: SettingsOptionViewType = .normal,
        titleStyle: SettingsTextStyle = .bodyS,
        @ViewBuilder titleAccessory: @escaping () -> TitleAccessory,
        @ViewBuilder trailingView: @escaping () -> TrailingView
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.type = type
        self.titleStyle = titleStyle
        self.titleAccessory = titleAccessory
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
        case .normal, .highlighted:
            // One step below the label; `.highlighted` still reads through `bgColor`.
            return Theme.colors.textSecondary
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

    var subtitleColor: Color {
        switch type {
        case .normal, .highlighted:
            return Theme.colors.textSecondary
        case .alert:
            return Theme.colors.alertError.opacity(Self.alertSubtitleOpacity)
        }
    }

    private static var alertSubtitleOpacity: Double { 0.8 }

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Icon(icon, color: iconColor, size: 20)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(title.localized)
                        .settingsText(titleStyle)
                        .foregroundStyle(fontColor)
                    titleAccessory()
                }

                if let subtitle {
                    Text(subtitle)
                        .settingsText(.caption)
                        .foregroundStyle(subtitleColor)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailingView()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .background(bgColor)
    }
}

extension SettingsOptionView where TitleAccessory == EmptyView {
    init(
        icon: ImageResource?,
        title: String,
        subtitle: String? = nil,
        type: SettingsOptionViewType = .normal,
        titleStyle: SettingsTextStyle = .bodyS,
        @ViewBuilder trailingView: @escaping () -> TrailingView
    ) {
        self.init(
            icon: icon,
            title: title,
            subtitle: subtitle,
            type: type,
            titleStyle: titleStyle,
            titleAccessory: { EmptyView() },
            trailingView: trailingView
        )
    }
}
