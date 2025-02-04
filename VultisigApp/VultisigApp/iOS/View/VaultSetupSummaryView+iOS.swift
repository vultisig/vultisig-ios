//
//  VaultSetupSummaryView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-02-04.
//

#if os(iOS)
import SwiftUI

extension VaultSetupSummaryView {
    var container: some View {
        ZStack {
            Background()
            main
        }
        .navigationBarBackButtonHidden(true)
    }
}
#endif
