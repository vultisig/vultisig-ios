//
//  VaultSetupSummaryView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-02-04.
//

#if os(macOS)
import SwiftUI

extension VaultSetupSummaryView {
    var container: some View {
        ZStack {
            Background()
            main
        }
    }
}
#endif
