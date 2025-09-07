//
//  FormExpandableSection.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 07/09/2025.
//

import SwiftUI

struct FormExpandableSection<Content: View, T: Hashable>: View {
    let title: String
    let isValid: Bool
    let value: String
    let showValue: Bool
    
    var focusedField: Binding<T?>
    let focusedFieldEquals: T
    var onExpand: (Bool) -> Void
    let content: () -> Content
    
    init(
        title: String,
        isValid: Bool,
        value: String,
        showValue: Bool,
        focusedField: Binding<T?>,
        focusedFieldEquals: T,
        onExpand: @escaping (Bool) -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.isValid = isValid
        self.value = value
        self.showValue = showValue
        self.focusedField = focusedField
        self.focusedFieldEquals = focusedFieldEquals
        self.onExpand = onExpand
        self.content = content
    }
    
    @State var isExpanded = false
    
    var body: some View {
        SendFormExpandableSection(isExpanded: isExpanded) {
            HStack(spacing: 12) {
                Text(title)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .frame(maxWidth: showValue && isValid ? nil : .infinity, alignment: .leading)
                
                HStack(spacing: 12) {
                    Text(value)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textExtraLight)
                    Spacer()
                    HStack {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(Theme.colors.alertSuccess)
                        Image(systemName: "pencil")
                            .foregroundColor(Theme.colors.textPrimary)
                    }
                }
                .showIf(showValue && isValid)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                isExpanded.toggle()
                onExpand(isExpanded)
            }
        } content: {
            GradientListSeparator()
            content()
        }
        .onChange(of: focusedField.wrappedValue) { _, newValue in
            guard let newValue else { return }
            isExpanded = newValue == focusedFieldEquals
        }
    }
}
