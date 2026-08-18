//
//  ViewExtension.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-24.
//

import SwiftUI

extension View {
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

    @ViewBuilder func supportsLiquidGlass<Content: View>(transform: (Self, Bool) -> Content) -> some View {
        if #available(iOS 26.0, *) {
            transform(self, true)
        } else {
            transform(self, false)
        }
    }
}
