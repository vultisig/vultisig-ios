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

/// `.settings` is the settings forms' field: a 52 tall card with a dim label and
/// placeholder and no outer gutter. `.settingsInput` is the same card with the
/// design's normal border, which shows validation colours. Everywhere else keeps
/// `.standard`.
enum CommonTextFieldAppearance {
    case standard, settings, settingsInput

    var isSettings: Bool {
        self != .standard
    }
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

    private static var settingsHeight: CGFloat { 52 }

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
                case .settings, .settingsInput:
                    Text(label)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .settingsText(.bodyS)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    textFieldContainer
                        .font(textFont)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .submitLabel(.done)
                        .colorScheme(.dark)
                        .frame(maxWidth: .infinity)

                    clearButton
                        .showIf(isEnabled)
                    trailingView()
                }
                .frame(height: appearance.isSettings ? nil : height)
                .frame(minHeight: appearance.isSettings ? height : nil)
                .font(Theme.fonts.bodyMMedium)
                .padding(.horizontal, horizontalPadding)
                .background(backgroundColor)
                .cornerRadius(cornerRadius)
                .overlay(border)
                .autocorrectionDisabled()
                .borderlessTextFieldStyle()
                .padding(outerPadding)

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
                .circleXmarkFilled,
                color: Theme.colors.textTertiary,
                size: appearance == .settingsInput ? 18 : 16
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
            } else if appearance.isSettings {
                TextField(
                    placeholder?.localized ?? .empty,
                    text: $text,
                    prompt: Text(placeholder?.localized ?? .empty).foregroundStyle(Theme.colors.textTertiary)
                )
            } else {
                TextField(placeholder?.localized ?? .empty, text: $text)
            }
        }
        .frame(height: appearance.isSettings ? nil : height)
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
        guard appearance == .standard else { return Self.settingsHeight }
        switch size {
        case .normal:
            return 56
        case .small:
            return 36
        }
    }

    var textFont: Font {
        appearance.isSettings ? Theme.fonts.bodySMedium : Theme.fonts.bodyMRegular
    }

    var horizontalPadding: CGFloat {
        appearance.isSettings ? 16 : 12
    }

    var outerPadding: CGFloat {
        appearance.isSettings ? 0 : 1
    }

    var backgroundColor: Color {
        appearance.isSettings ? Color(hex: "051937") : Theme.colors.bgSurface1
    }

    var cornerRadius: CornerRadius {
        appearance.isSettings ? Theme.radius.lg : Theme.radius.md
    }

    @ViewBuilder
    var border: some View {
        switch appearance {
        case .standard:
            cornerRadius.shape
                .stroke(borderColor, lineWidth: borderWidth)
        case .settings:
            cornerRadius.shape
                .strokeBorder(Theme.colors.borderExtraLight, lineWidth: 1)
        case .settingsInput:
            cornerRadius.shape
                .strokeBorder(settingsInputBorderColor, lineWidth: 1)
        }
    }

    private var settingsInputBorderColor: Color {
        if let isValid, isValid {
            return Theme.colors.alertSuccess
        }
        return hasError ? invalidColor : Theme.colors.borderNormal
    }
}
