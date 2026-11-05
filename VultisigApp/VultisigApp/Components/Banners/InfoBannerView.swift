//
//  Banner.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 19/08/2025.
//

import SwiftUI

enum InfoBannerType {
    case info
    case warning
    case error
    case success
}

/// `.settings`: the settings forms' banner, radius 24 with a softer border.
enum InfoBannerAppearance {
    case standard, settings
}

struct InfoBannerView: View {
    private let settingsFillOpacity = 0.05

    let description: String
    let type: InfoBannerType
    let leadingIcon: ImageResource?
    let iconColor: Color?
    let trailingIcon: ImageResource?
    let appearance: InfoBannerAppearance
    let onClose: (() -> Void)?

    init(
        description: String,
        type: InfoBannerType,
        leadingIcon: ImageResource?,
        iconColor: Color? = nil,
        trailingIcon: ImageResource? = nil,
        appearance: InfoBannerAppearance = .standard,
        onClose: (() -> Void)? = nil
    ) {
        self.description = description
        self.type = type
        self.leadingIcon = leadingIcon
        self.iconColor = iconColor
        self.trailingIcon = trailingIcon
        self.appearance = appearance
        self.onClose = onClose
    }

    var body: some View {
        HStack(spacing: 12) {
            if let leadingIcon {
                Icon(leadingIcon, color: iconColor ?? fontColor, size: 16)
            }

            descriptionText
                .foregroundStyle(fontColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if let trailingIcon {
                Icon(trailingIcon, color: iconColor ?? fontColor, size: 16)
            }

            if let onClose {
                Spacer()
                Button(action: onClose) {
                    Icon(.xmark, color: Theme.colors.textSecondary, size: 12)
                        .padding(8)
                        .background(Circle().fill(Theme.colors.bgSurface2))
                }
            }
        }
        .padding(16)
        .background(
            cornerRadius.shape
                .inset(by: 1)
                .fill(bgColor)
                .stroke(borderColor, lineWidth: 1)
        )
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var descriptionText: some View {
        switch appearance {
        case .standard:
            Text(description).font(Theme.fonts.footnote)
        case .settings:
            Text(description).settingsText(.footnote)
        }
    }

    private var cornerRadius: CornerRadius {
        switch appearance {
        case .standard: Theme.radius.md
        case .settings: Theme.radius.xl
        }
    }

    private var alertBorderOpacity: Double {
        switch appearance {
        case .standard: 0.35
        case .settings: 0.25
        }
    }

    var fontColor: Color {
        switch type {
        case .info:
            Theme.colors.textSecondary
        case .warning:
            Theme.colors.alertWarning
        case .error:
            Theme.colors.alertError
        case .success:
            Theme.colors.alertSuccess
        }
    }

    var bgColor: Color {
        switch type {
        case .info:
            Theme.colors.bgNeutral
        case .warning:
            appearance == .settings ? Theme.colors.alertWarning.opacity(settingsFillOpacity) : Theme.colors.bgAlert
        case .error:
            appearance == .settings ? Theme.colors.alertError.opacity(settingsFillOpacity) : Theme.colors.bgError
        case .success:
            Theme.colors.bgSuccess
        }
    }

    var borderColor: Color {
        switch type {
        case .info:
            Theme.colors.bgSurface2
        case .warning:
            Theme.colors.alertWarning.opacity(alertBorderOpacity)
        case .error:
            Theme.colors.alertError.opacity(alertBorderOpacity)
        case .success:
            Theme.colors.bgSuccess.opacity(0.35)
        }
    }
}

#Preview {
    InfoBannerView(description: "This is a test", type: .info, leadingIcon: nil)
}
