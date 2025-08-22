//
//  ScreenToolbarModifier.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/08/2025.
//

import SwiftUI

public struct ScreenToolbarModifier<Trailing: View>: ViewModifier {
    private let trailing: () -> Trailing

    public init(
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.trailing = trailing
    }

    public func body(content: Content) -> some View {
        #if os(macOS)
        content
            .environment(\.screenToolbarTrailing, AnyView(trailing()))
        #else
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { trailing() }
            }
        #endif
    }
}

public extension View {
    /// Cross-platform toolbar: on iOS it maps to `.toolbar`,
    /// on macOS it injects views for `GeneralMacHeader` to render.
    func screenToolbar<Trailing: View>(
        @ViewBuilder trailing: @escaping () -> Trailing
    ) -> some View {
        modifier(ScreenToolbarModifier(trailing: trailing))
    }
}
