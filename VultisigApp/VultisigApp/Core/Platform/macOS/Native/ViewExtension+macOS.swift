//
//  ViewExtension+macOS.swift
//  VultisigApp
//

#if os(macOS)
import SwiftUI

extension View {
    /// The macOS half of `hideKeyboard()`.
    ///
    /// A no-op: there is no software keyboard to put away. It exists so shared
    /// screens can release the keyboard on the way to another screen without
    /// wrapping every call site in `#if os(iOS)`.
    func hideKeyboard() {}
}
#endif
