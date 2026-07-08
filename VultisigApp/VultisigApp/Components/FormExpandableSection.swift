//
//  FormExpandableSection.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 07/09/2025.
//

import SwiftUI

struct FormExpandableSection<Content: View, T: Hashable, ValueView: View>: View {
    let title: String
    let isValid: Bool
    let showValue: Bool
    /// Corner radius of the bordered card. Defaults to the shared form value;
    /// only the limit-swap sections override it to match their Figma radius.
    let cornerRadius: CGFloat

    var focusedField: Binding<T?>
    let focusedFieldEquals: [T]
    var onExpand: (Bool) -> Void
    let content: () -> Content
    let valueView: () -> ValueView

    init(
        title: String,
        isValid: Bool,
        value: String,
        showValue: Bool,
        focusedField: Binding<T?>,
        focusedFieldEquals: T,
        cornerRadius: CGFloat = 12,
        onExpand: @escaping (Bool) -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) where ValueView == AnyView {
        self.init(
            title: title,
            isValid: isValid,
            showValue: showValue,
            focusedField: focusedField,
            focusedFieldEquals: focusedFieldEquals,
            cornerRadius: cornerRadius,
            onExpand: onExpand,
            content: content,
            valueView: {
                AnyView(Text(value)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle))
            }
        )
    }

    init(
        title: String,
        isValid: Bool,
        value: String,
        showValue: Bool,
        focusedField: Binding<T?>,
        focusedFieldEquals: [T],
        cornerRadius: CGFloat = 12,
        onExpand: @escaping (Bool) -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) where ValueView == AnyView {
        self.init(
            title: title,
            isValid: isValid,
            showValue: showValue,
            focusedField: focusedField,
            focusedFieldEquals: focusedFieldEquals,
            cornerRadius: cornerRadius,
            onExpand: onExpand,
            content: content,
            valueView: {
                AnyView(Text(value)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle))
            }
        )
    }

    init(
        title: String,
        isValid: Bool,
        showValue: Bool,
        focusedField: Binding<T?>,
        focusedFieldEquals: T,
        cornerRadius: CGFloat = 12,
        onExpand: @escaping (Bool) -> Void,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder valueView: @escaping () -> ValueView
    ) {
        self.title = title
        self.isValid = isValid
        self.showValue = showValue
        self.cornerRadius = cornerRadius
        self.focusedField = focusedField
        self.focusedFieldEquals = [focusedFieldEquals]
        self.onExpand = onExpand
        self.content = content
        self.valueView = valueView
    }

    init(
        title: String,
        isValid: Bool,
        showValue: Bool,
        focusedField: Binding<T?>,
        focusedFieldEquals: [T],
        cornerRadius: CGFloat = 12,
        onExpand: @escaping (Bool) -> Void,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder valueView: @escaping () -> ValueView
    ) {
        self.title = title
        self.isValid = isValid
        self.showValue = showValue
        self.cornerRadius = cornerRadius
        self.focusedField = focusedField
        self.focusedFieldEquals = focusedFieldEquals
        self.onExpand = onExpand
        self.content = content
        self.valueView = valueView
    }

    @State var isExpanded = false

    var body: some View {
        SendFormExpandableSection(isExpanded: isExpanded, cornerRadius: cornerRadius) {
            FormSectionHeader(
                title: title,
                showValue: showValue,
                indicator: isValid && !isExpanded ? .editable : .hidden,
                action: {
                    isExpanded.toggle()
                    onExpand(isExpanded)
                },
                valueView: valueView
            )
        } content: {
            GradientListSeparator()
            content()
        }
        .onChange(of: focusedField.wrappedValue) { _, newValue in
            guard let newValue else { return }
            isExpanded = focusedFieldEquals.contains(newValue)
        }
    }
}
