//
//  KeygenView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-18.
//

#if os(iOS)
import SwiftUI

extension KeygenView {
    private var idiom : UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
    
    var content: some View {
        VStack {
            fields
            instructions
            appVersion
        }
        .navigationTitle(NSLocalizedString("joinKeygen", comment: ""))
        .navigationDestination(isPresented: $viewModel.isLinkActive) {
            BackupVaultNowView(vault: vault)
        }
        .task {
            await viewModel.startKeygen(
                context: context,
                defaultChains: settingsDefaultChainViewModel.defaultChains
            )
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            setData()
        }
        .onDisappear(){
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
    
    var keygenViewInstructions: some View {
        KeygenViewInstructions()
            .padding(.bottom, 30)
    }
    
    var appVersion: some View {
        return VStack {
            Text("Vultisig APP V\(version ?? "1")")
            Text("(Build \(build ?? "1"))")
        }
        .textCase(.uppercase)
        .font(.body14Menlo)
        .foregroundColor(.turquoise600)
        .padding(.bottom, idiom == .pad ? 30 : 0)
    }
}
#endif
