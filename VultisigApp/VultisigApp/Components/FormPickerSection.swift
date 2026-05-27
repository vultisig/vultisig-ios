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
    let showValue: Bool
    let onTap: () -> Void
    let valueView: () -> ValueView

    init(
        title: String,
        value: String,
        showValue: Bool,
        onTap: @escaping () -> Void
    ) where ValueView == AnyView {
        self.init(
            title: title,
            showValue: showValue,
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
        showValue: Bool,
        onTap: @escaping () -> Void,
        @ViewBuilder valueView: @escaping () -> ValueView
    ) {
        self.title = title
        self.showValue = showValue
        self.onTap = onTap
        self.valueView = valueView
    }

    var body: some View {
        SendFormExpandableSection(isExpanded: false) {
            FormSectionHeader(
                title: title,
                showValue: showValue,
                indicator: .picker,
                action: onTap,
                valueView: valueView
            )
        } content: {
            EmptyView()
        }
    }
}
