//
//  SwapCryptoAmountTextField+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-11.
//

#if os(iOS)
import SwiftUI

extension SwapCryptoAmountTextField {
    func container(_ customBiding: Binding<String>) -> some View {
        content(customBiding)
            .textInputAutocapitalization(.never)
            .keyboardType(.decimalPad)
            .textContentType(.oneTimeCode)
    }
}
#endif
