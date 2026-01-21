//
//  SwapVerifyView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-07.
//

#if os(iOS)
import SwiftUI

extension SwapVerifyView {
    var container: some View {
        content
            .toolbar {
                toolbarItemWithHiddenBackground(placement: Placement.topBarTrailing.getPlacement()) {
                    refreshCounter
                }
            }
    }

    var fields: some View {
        ScrollView {
            VStack(spacing: 30) {
                Spacer()
                summary
                checkboxes
                Spacer()
            }
            .padding(.horizontal, 16)
        }
    }
}
#endif
