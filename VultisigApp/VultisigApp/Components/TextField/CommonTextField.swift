//
//  CommonTextField.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/08/2025.
//

import SwiftUI

enum CommonTextFieldSize {
    case normal, small
}

/// How the field renders its invalid state. `.error` is the shared default
/// (red border + red caption). `.warning` uses the softer amber treatment the
/// 2026 redesign applies to the recipient-address field: a 0.5px amber border
/// and a 12pt amber caption.
enum CommonTextFieldErrorStyle {
    case error, warning
}

/// `.settings`: a 52 tall card with a dim label and placeholder, no outer gutter.
/// `.settingsInput`: the same card with a normal border that shows validation colours.
/// `.settingsForm`: radius 12 with a light border, for fields inside a form section.
/// `.settingsCode`: 56 tall, radius 12, showing validation colours, for short codes.
enum CommonTextFieldAppearance {
    case standard, settings, settingsInput, settingsForm, settingsCode
}

private struct CommonTextFieldMetrics {
    let height: CGFloat
    let textFont: Font
    let horizontalPadding: CGFloat
    let outerPadding: CGFloat
    let cornerRadius: CornerRadius
    let clearIconSize: CGFloat
    var clearIcon: ImageResource = .circleXmarkFilled
}

struct CommonTextField<TrailingView: View>: View {
    @Environment(\.isEnabled) var isEnabled
    @Binding var text: String
    let label: String?
    let placeholder: String?
    @Binding var isSecure: Bool
    @Binding var error: String?
    @Binding var isValid: Bool?
    let showErrorText: Bool
    let isScrollable: Bool
    let labelStyle: TextFieldLabelStyle
    let size: CommonTextFieldSize
    let errorStyle: CommonTextFieldErrorStyle
    let appearance: CommonTextFieldAppearance

    let trailingView: () -> TrailingView

    private let settingsHeight: CGFloat = 52

    init(
        text: Binding<String>,
        label: String? = nil,
        placeholder: String?,
        isSecure: Binding<Bool> = .constant(false),
        error: Binding<String?> = .constant(nil),
        isValid: Binding<Bool?> = .constant(nil),
        showErrorText: Bool = true,
        isScrollable: Bool = false,
        labelStyle: TextFieldLabelStyle = .primary,
        size: CommonTextFieldSize = .normal,
        errorStyle: CommonTextFieldErrorStyle = .error,
        appearance: CommonTextFieldAppearance = .standard,
        @ViewBuilder trailingView: @escaping () -> TrailingView
    ) {
        self._text = text
        self.label = label
        self.placeholder = placeholder
        self._isSecure = isSecure
        self._error = error
        self.showErrorText = showErrorText
        self.isScrollable = isScrollable
        self.trailingView = trailingView
        self.labelStyle = labelStyle
        self.size = size
        self.errorStyle = errorStyle
        self.appearance = appearance
        self._isValid = isValid
    }

    init(
        text: Binding<String>,
        label: String? = nil,
        placeholder: String?,
        isSecure: Binding<Bool> = .constant(false),
        error: Binding<String?> = .constant(nil),
        isValid: Binding<Bool?> = .constant(nil),
        showErrorText: Bool = true,
        isScrollable: Bool = false,
        labelStyle: TextFieldLabelStyle = .primary,
        size: CommonTextFieldSize = .normal,
        errorStyle: CommonTextFieldErrorStyle = .error,
        appearance: CommonTextFieldAppearance = .standard
    ) where TrailingView == EmptyView {
        self.init(
            text: text,
            label: label,
            placeholder: placeholder,
            isSecure: isSecure,
            error: error,
            isValid: isValid,
            showErrorText: showErrorText,
            isScrollable: isScrollable,
            labelStyle: labelStyle,
            size: size,
            errorStyle: errorStyle,
            appearance: appearance,
            trailingView: { EmptyView() }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let label {
                switch appearance {
                case .standard:
                    Text(label)
                        .foregroundStyle(labelColor)
                        .font(labelFont)
                case .settings, .settingsInput, .settingsForm, .settingsCode:
                    Text(label)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .settingsText(.bodyS)
                }
            }

            VStack(alignment: .leading, spacing: appearance == .settingsCode ? 8 : 4) {
                HStack {
                    textFieldContainer
                        .font(metrics.textFont)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .submitLabel(.done)
                        .colorScheme(.dark)
                        .frame(maxWidth: .infinity)

                    clearButton
                        .showIf(isEnabled)
                    trailingView()
                }
                .frame(height: height)
                .font(Theme.fonts.bodyMMedium)
                .padding(.horizontal, metrics.horizontalPadding)
                .background(Theme.colors.bgSurface1)
                .cornerRadius(metrics.cornerRadius)
                .overlay(border)
                .autocorrectionDisabled()
                .borderlessTextFieldStyle()
                .padding(metrics.outerPadding)

                if let error, showErrorText {
                    Text(error.localized)
                        .foregroundStyle(errorCaptionColor)
                        .font(errorCaptionFont)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .animation(.easeInOut, value: error)
    }

    var clearButton: some View {
        Button {
            text = ""
        } label: {
            Icon(
                metrics.clearIcon,
                color: Theme.colors.textTertiary,
                size: metrics.clearIconSize
            )
        }
        .buttonStyle(.plain)
        .opacity(text.isEmpty ? 0 : 1)
    }

    var hasError: Bool {
        error != nil && error != .empty
    }

    var invalidColor: Color {
        switch errorStyle {
        case .error:
            return Theme.colors.alertError
        case .warning:
            return Theme.colors.alertWarning
        }
    }

    var borderColor: Color {
        if let isValid, isValid {
            return Theme.colors.alertSuccess
        }

        return hasError ? invalidColor : Theme.colors.border
    }

    var borderWidth: CGFloat {
        guard hasError else { return 1 }
        switch errorStyle {
        case .error:
            return 1
        case .warning:
            return 0.5
        }
    }

    var errorCaptionColor: Color {
        invalidColor
    }

    var errorCaptionFont: Font {
        if appearance == .settingsCode {
            return Theme.fonts.caption12
        }
        switch errorStyle {
        case .error:
            return Theme.fonts.footnote
        case .warning:
            return Theme.fonts.caption12
        }
    }

    @ViewBuilder
    var textFieldContainer: some View {
        if isScrollable {
            ScrollView(.horizontal, showsIndicators: false) {
                textField
                    .frame(minWidth: 200)
            }
        } else {
            textField
        }
    }

    @ViewBuilder
    var textField: some View {
        Group {
            if isSecure {
                SecureField(placeholder?.localized ?? .empty, text: $text)
            } else if appearance != .standard {
                TextField(
                    placeholder?.localized ?? .empty,
                    text: $text,
                    prompt: Text(placeholder?.localized ?? .empty).foregroundStyle(Theme.colors.textTertiary)
                )
            } else {
                TextField(placeholder?.localized ?? .empty, text: $text)
            }
        }
        .frame(height: height)
    }

    var labelFont: Font {
        switch labelStyle {
        case .primary:
            Theme.fonts.bodySMedium
        case .secondary:
            Theme.fonts.footnote
        }
    }

    var labelColor: Color {
        switch labelStyle {
        case .primary:
            Theme.colors.textPrimary
        case .secondary:
            Theme.colors.textTertiary
        }
    }

    enum TextFieldLabelStyle {
        case primary
        case secondary
    }

    var height: CGFloat {
        metrics.height
    }

    private var standardHeight: CGFloat {
        switch size {
        case .normal:
            56
        case .small:
            36
        }
    }

    private var metrics: CommonTextFieldMetrics {
        switch appearance {
        case .standard:
            CommonTextFieldMetrics(
                height: standardHeight,
                textFont: Theme.fonts.bodyMRegular,
                horizontalPadding: 12,
                outerPadding: 1,
                cornerRadius: Theme.radius.md,
                clearIconSize: 16
            )
        case .settings:
            CommonTextFieldMetrics(
                height: settingsHeight,
                textFont: Theme.fonts.bodySMedium,
                horizontalPadding: 16,
                outerPadding: 0,
                cornerRadius: Theme.radius.lg,
                clearIconSize: 16
            )
        case .settingsInput:
            CommonTextFieldMetrics(
                height: settingsHeight,
                textFont: Theme.fonts.bodySMedium,
                horizontalPadding: 16,
                outerPadding: 0,
                cornerRadius: Theme.radius.lg,
                clearIconSize: 18
            )
        case .settingsForm:
            CommonTextFieldMetrics(
                height: settingsHeight,
                textFont: Theme.fonts.bodySMedium,
                horizontalPadding: 16,
                outerPadding: 0,
                cornerRadius: Theme.radius.md,
                clearIconSize: 18
            )
        case .settingsCode:
            CommonTextFieldMetrics(
                height: standardHeight,
                textFont: Theme.fonts.bodyMMedium,
                horizontalPadding: 16,
                outerPadding: 0,
                cornerRadius: Theme.radius.md,
                clearIconSize: 20,
                clearIcon: .xmark
            )
        }
    }

    @ViewBuilder
    var border: some View {
        switch appearance {
        case .standard:
            metrics.cornerRadius.shape
                .stroke(borderColor, lineWidth: borderWidth)
        case .settings:
            metrics.cornerRadius.shape
                .strokeBorder(Theme.colors.borderExtraLight, lineWidth: 1)
        case .settingsInput:
            metrics.cornerRadius.shape
                .strokeBorder(settingsInputBorderColor, lineWidth: 1)
        case .settingsForm:
            metrics.cornerRadius.shape
                .strokeBorder(hasError ? invalidColor : Theme.colors.borderExtraLight, lineWidth: 1)
        case .settingsCode:
            metrics.cornerRadius.shape
                .strokeBorder(settingsCodeBorderColor, lineWidth: 1)
        }
    }

    private var settingsCodeBorderColor: Color {
        switch isValid {
        case .some(true): Theme.colors.alertSuccess
        case .some(false): invalidColor
        case nil: hasError ? invalidColor : Theme.colors.borderLight
        }
    }

    private var settingsInputBorderColor: Color {
        if let isValid, isValid {
            return Theme.colors.alertSuccess
        }
        return hasError ? invalidColor : Theme.colors.borderNormal
    }
}
