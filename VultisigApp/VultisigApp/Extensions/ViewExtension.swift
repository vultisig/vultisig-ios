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
    
    func onFirstAppear(perform: @escaping () -> Void) -> some View {
        modifier(OnFirstAppear(perform: perform))
    }
    
    func borderlessTextFieldStyle() -> some View {
        self.textFieldStyle(PlainTextFieldStyle())
    }
}
