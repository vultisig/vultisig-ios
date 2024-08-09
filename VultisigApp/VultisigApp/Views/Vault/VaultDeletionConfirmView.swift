//
//  VaultDeletionConfirmView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-05.
//

import SwiftUI
import SwiftData

struct VaultDeletionConfirmView: View {
    let vault: Vault
    
    @State var permanentDeletionCheck = false
    @State var canLoseFundCheck = false
    @State var vaultBackupCheck = false
    
    @State var showAlert = false
    @State var navigateBackToHome = false
    
    @State var isPhoneSE = false
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var homeViewModel: HomeViewModel
    
#if os(iOS)
    private var idiom : UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
#endif
    
    let vaults: [Vault]
    
    var body: some View {
        ZStack {
            GeometryReader { proxy in
                Background()
                    .onAppear {
                        setData(proxy)
                    }
            }
            
            main
        }
        .navigationBarBackButtonHidden(true)
#if os(iOS)
        .navigationTitle(NSLocalizedString("deleteVaultTitle", comment: "Delete Vault"))
        .toolbar {
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                NavigationBackButton()
            }
        }
#endif
    }
    
    var main: some View {
        VStack {
#if os(macOS)
            headerMac
#endif
            view
        }
    }
    
    var headerMac: some View {
        GeneralMacHeader(title: "deleteVaultTitle")
    }
    
    var view: some View {
        VStack(spacing: 32) {
            logo
            details
            
#if os(iOS)
            if idiom == .pad {
                Spacer()
            }
#elseif os(macOS)
            Spacer()
#endif
            
            checkboxes
            button
        }
#if os(iOS)
        .padding(18)
        .padding(.top, 12)
#elseif os(macOS)
        .padding(.horizontal, 25)
#endif
        .navigationDestination(isPresented: $navigateBackToHome) {
            HomeView(selectedVault: vaults.first, showVaultsList: true)
        }
        .alert(isPresented: $showAlert) {
            alert
        }
    }
    
    var logo: some View {
#if os(iOS)
        let spacing: CGFloat = 28
#elseif os(macOS)
        let spacing: CGFloat = 12
#endif
                
        return VStack(spacing: spacing) {
            Image(systemName: "exclamationmark.triangle.fill")
#if os(iOS)
                .font(.title80Menlo)
#elseif os(macOS)
                .font(.title40MenloBold)
#endif
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.neutral0, Color.alertRed)
            
            Text(NSLocalizedString("youArePermanentlyDeletingVault", comment: ""))
                .font(.body16MenloBold)
                .foregroundColor(.neutral0)
#if os(iOS)
                .frame(maxWidth: 200)
#endif
                .multilineTextAlignment(.center)
                .fixedSize()
        }
    }
    
    var checkboxes: some View {
#if os(iOS)
        let spacing: CGFloat = isPhoneSE ? 16 : 32
#elseif os(macOS)
        let spacing: CGFloat = 12
#endif
                
        return VStack(spacing: spacing) {
            Checkbox(isChecked: $permanentDeletionCheck, text: "vaultWillBeDeletedPermanentlyPrompt")
            Checkbox(isChecked: $canLoseFundCheck, text: "canLoseFundsPrompt")
            Checkbox(isChecked: $vaultBackupCheck, text: "madeVaultBackupPrompt")
        }
    }
    
    var details: some View {
        VaultDeletionDetails(vault: vault, isPhoneSE: isPhoneSE)
    }
    
    var button: some View {
        Button {
            delete()
        } label: {
            FilledButton(title: "deleteVaultTitle", background: Color.alertRed)
        }
#if os(macOS)
        .padding(.bottom, 20)
#endif
    }
    
    private func delete() {
        guard allFieldsChecked() else {
            showAlert = true
            return
        }
        homeViewModel.selectedVault = nil
        modelContext.delete(vault)
        do {
            try modelContext.save()
        } catch {
            print("Error: \(error)")
        }
        ApplicationState.shared.currentVault = nil
        navigateBackToHome = true
    }
    
    private func allFieldsChecked() -> Bool {
        permanentDeletionCheck && canLoseFundCheck && vaultBackupCheck
    }
    
    var alert: Alert {
        Alert(
            title: Text(NSLocalizedString("reviewConditions", comment: "")),
            message: Text(NSLocalizedString("reviewConditionsMessage", comment: "")),
            dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
        )
    }
    
    private func setData(_ proxy: GeometryProxy) {
        let screenWidth = proxy.size.width
        
        if screenWidth<380 {
            isPhoneSE = true
        }
    }
}

#Preview {
    VaultDeletionConfirmView(vault: Vault.example, vaults: [])
}
