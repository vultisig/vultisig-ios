//
//  FormPickerSection.swift
//  VultisigApp
//
//  Sibling of `FormExpandableSection` for rows whose value is staged
//  through an external picker / sheet. Reuses the shared
//  `FormSectionHeader` for the title row and `SendFormExpandableSection`
//  for the bordered container — but never expands; tapping anywhere on
//  the row fires `onTap`.
//

import SwiftUI

struct FormPickerSection<ValueView: View>: View {
    let title: String
    let isValid: Bool
    let onTap: () -> Void
    let valueView: () -> ValueView

    init(
        title: String,
        value: String,
        isValid: Bool,
        onTap: @escaping () -> Void
    ) where ValueView == AnyView {
        self.init(
            title: title,
            isValid: isValid,
            onTap: onTap,
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
        onTap: @escaping () -> Void,
        @ViewBuilder valueView: @escaping () -> ValueView
    ) {
        self.title = title
        self.isValid = isValid
        self.onTap = onTap
        self.valueView = valueView
    }

    var body: some View {
        SendFormExpandableSection(isExpanded: false) {
            FormSectionHeader(
                title: title,
                showValue: isValid,
                indicator: isValid ? .editable : .picker,
                action: onTap,
                valueView: valueView
            )
        } content: {
            EmptyView()
        }
    }
}
