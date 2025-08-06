//
//  SwapCoinPickerView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-04-28.
//

#if os(macOS)
import SwiftUI

extension SwapCoinPickerView {
    var body: some View {
        Screen(title: NSLocalizedString("selectAsset", comment: "")) {
            content
        }.frame(width: 700, height: 450)
    }
}
#endif
