//
//  View+ListSectionSpacing.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/09/2025.
//

import SwiftUI

extension View {
    func customSectionSpacing(_ spacing: CGFloat) -> some View {
        #if os(macOS)
        self
        #else
        self.listSectionSpacing(spacing)
        #endif
    }

    func groupedListStyle() -> some View {
#if os(macOS)
        self.listStyle(.plain)
#else
        self.listStyle(.grouped)
#endif
    }
}
