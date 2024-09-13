//
//  VultisigLogo+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-13.
//

#if os(macOS)
import SwiftUI

extension VultisigLogo {
    var container: some View {
        content
            .scaleEffect(0.9)
            .offset(y: 12)
    }
}
#endif
