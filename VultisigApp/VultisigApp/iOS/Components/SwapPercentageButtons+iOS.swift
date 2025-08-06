//
//  SwapPercentageButtons+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-25.
//

#if os(iOS)
import SwiftUI

extension SwapPercentageButtons {
    var container: some View {
        VStack(spacing: 0) {
            separator
            content
            separator
        }
    }
    
    var content: some View {
        buttons
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(Theme.colors.bgPrimary)
    }
}
#endif
