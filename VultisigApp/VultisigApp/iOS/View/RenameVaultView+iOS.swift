//
//  RenameVaultView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(iOS)
import SwiftUI

extension RenameVaultView {
    var content: some View {
        ZStack {
            Background()
            main
        }
        .navigationTitle(NSLocalizedString("renameVault", comment: "Edit Rename Vault View title"))
    }
    
    var main: some View {
        view
    }
    
    var view: some View {
        VStack {
            fields
            Spacer()
            button
        }
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text(NSLocalizedString("error", comment: "")),
                message: Text(errorMessage),
                dismissButton: .default(Text("ok"))
            )
        }
    }
}
#endif
