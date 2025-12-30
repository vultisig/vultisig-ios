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
        onExpand: @escaping (Bool) -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) where ValueView == AnyView {
        self.init(
            title: title,
            isValid: isValid,
            showValue: showValue,
            focusedField: focusedField,
            focusedFieldEquals: focusedFieldEquals,
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
        onExpand: @escaping (Bool) -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) where ValueView == AnyView {
        self.init(
            title: title,
            isValid: isValid,
            showValue: showValue,
            focusedField: focusedField,
            focusedFieldEquals: focusedFieldEquals,
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
        onExpand: @escaping (Bool) -> Void,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder valueView: @escaping () -> ValueView
    ) {
        self.title = title
        self.isValid = isValid
        self.showValue = showValue
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
        onExpand: @escaping (Bool) -> Void,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder valueView: @escaping () -> ValueView
    ) {
        self.title = title
        self.isValid = isValid
        self.showValue = showValue
        self.focusedField = focusedField
        self.focusedFieldEquals = focusedFieldEquals
        self.onExpand = onExpand
        self.content = content
        self.valueView = valueView
    }
    
    @State var isExpanded = false
    
    var body: some View {
        SendFormExpandableSection(isExpanded: isExpanded) {
            Button {
                isExpanded.toggle()
                onExpand(isExpanded)
            } label: {
                HStack(spacing: 12) {
                    Text(title)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .frame(maxWidth: showValue && isValid ? nil : .infinity, alignment: .leading)
                    
                    if isValid && !isExpanded {
                        HStack(spacing: 12) {
                            valueView()
                                .showIf(showValue)
                            Spacer()
                            HStack {
                                Image(systemName: "checkmark.circle")
                                    .foregroundColor(Theme.colors.alertSuccess)
                                Image(systemName: "pencil")
                                    .foregroundColor(Theme.colors.textPrimary)
                            }
                        }
                    } else {
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
