//
//  VaultPairDetailView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(iOS)
import SwiftUI

extension VaultPairDetailView {
    var content: some View {
        ZStack {
            Background()
            main
        }
        .navigationTitle(NSLocalizedString("vaultDetailsTitle", comment: "View your vault details"))
    }
    
    var main: some View {
        view
    }
    
    var view: some View {
        cells
    }
}
#endif
