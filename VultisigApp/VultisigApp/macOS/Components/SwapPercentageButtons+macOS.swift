//
//  SwapPercentageButtons+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-25.
//

#if os(macOS)
import SwiftUI

extension SwapPercentageButtons {
    var container: some View {
        content
    }
    
    var content: some View {
        buttons
    }
}
#endif
