//
//  SwapCryptoAmountTextField+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-11.
//

#if os(macOS)
import SwiftUI

extension SwapCryptoAmountTextField {
    func container(_ customBiding: Binding<String>) -> some View {
        content(customBiding)
    }
}
#endif
