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
            .padding(.vertical, 12)
    }

    var fields: some View {
        ScrollView {
            VStack(spacing: 30) {
                Spacer()
                summary
                checkboxes
                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .padding(.horizontal, -24)
    }
}
#endif
