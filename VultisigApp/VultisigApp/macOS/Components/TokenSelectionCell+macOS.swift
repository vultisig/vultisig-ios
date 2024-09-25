//
//  TokenSelectionCell+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-10.
//

#if os(macOS)
import SwiftUI

extension TokenSelectionCell {
    var container: some View {
        content
            .scaleEffect(2)
            .offset(x: -12)
    }
}
#endif
