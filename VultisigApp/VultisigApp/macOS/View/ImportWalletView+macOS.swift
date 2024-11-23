//
//  ImportWalletView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-01.
//

#if os(macOS)
import SwiftUI

extension ImportWalletView {
    var content: some View {
        ZStack {
            Background()
            main
        }
        .onDrop(of: [.data], isTargeted: $isUploading) { providers -> Bool in
            backupViewModel.handleOnDrop(providers: providers)
        }
    }
    
    var main: some View {
        VStack {
            headerMac
            view
        }
    }
}
#endif
