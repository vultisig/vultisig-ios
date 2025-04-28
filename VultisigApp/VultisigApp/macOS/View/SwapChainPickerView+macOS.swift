//
//  SwapChainPickerView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-04-28.
//

#if os(macOS)
import SwiftUI

extension SwapChainPickerView {
    var body: some View {
        content
            .frame(width: 700, height: 450)
    }
}
#endif
