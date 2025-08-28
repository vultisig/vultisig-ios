//
//  ViewExtension.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-24.
//

import SwiftUI

extension View {
    func focusNextField<F: RawRepresentable>(_ field: FocusState<F?>.Binding) where F.RawValue == Int {
            guard let currentValue = field.wrappedValue else { return }
            let nextValue = currentValue.rawValue + 1
            if let newValue = F.init(rawValue: nextValue) {
                field.wrappedValue = newValue
            }
        }
    
    func focusPreviousField<F: RawRepresentable>(_ field: FocusState<F?>.Binding) where F.RawValue == Int {
        guard let currentValue = field.wrappedValue else { return }
        let nextValue = currentValue.rawValue - 1
        if let newValue = F.init(rawValue: nextValue) {
            field.wrappedValue = newValue
        }
    }
    
    func borderlessTextFieldStyle() -> some View {
        self.textFieldStyle(PlainTextFieldStyle())
    }
    
    @ViewBuilder
    func showIf(_ shouldShow: Bool) -> some View {
        if shouldShow {
            self
        }
    }
    
    @ViewBuilder
    func unwrap<T, Content: View>(_ value: T?, transform: (Self, T) -> Content) -> some View {
        if let value {
            transform(self, value)
        } else {
            self
        }
    }
    
    /// Applies the given transform if the given condition evaluates to `true`.
    /// - Parameters:
    ///   - condition: The condition to evaluate.
    ///   - transform: The transform to apply to the source `View`.
    /// - Returns: Either the original `View` or the modified `View` if the condition is `true`.
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
