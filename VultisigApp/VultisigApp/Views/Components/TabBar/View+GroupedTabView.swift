//
//  View+GroupedTabView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 15/09/2025.
//

import SwiftUI

extension View {
    @ViewBuilder
    func groupedTabViewStyle() -> some View {
        #if os(macOS)
            if #available(macOS 15.0, *) {
                self.tabViewStyle(.grouped)
            } else {
                self
            }
        #else
        self
        #endif
    }
}
