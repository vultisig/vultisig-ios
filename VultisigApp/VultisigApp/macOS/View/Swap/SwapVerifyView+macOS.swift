//
//  SwapVerifyView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-07.
//

#if os(macOS)
import SwiftUI

extension SwapVerifyView {
    var container: some View {
        content
            .padding(.horizontal, 25)
    }
}
#endif
