//
//  FastVaultSetPasswordView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-18.
//

#if os(iOS)
import SwiftUI

extension FastVaultSetHintView {

    var content: some View {
        ZStack {
            Background()
            main
        }
        .navigationTitle(NSLocalizedString("", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }
    
    var main: some View {
        view
            .onChange(of: isLinkActive) { _, isActive in
                guard isActive else { return }
                router.navigate(to: KeygenRoute.peerDiscovery(
                    tssType: tssType,
                    vault: vault,
                    selectedTab: selectedTab,
                    fastSignConfig: fastSignConfig,
                    keyImportInput: nil
                ))
            }
    }
    
    var view: some View {
        VStack {
            hintField
            Spacer()
            buttons
        }
    }
}
#endif
