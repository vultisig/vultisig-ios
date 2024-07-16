//
//  AddressBookView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-10.
//

import SwiftUI

struct AddressBookView: View {
    let vault: Vault?
    
    @EnvironmentObject var addressBookViewModel: AddressBookViewModel
    @EnvironmentObject var coinSelectionViewModel: CoinSelectionViewModel
    
    @State var title: String = ""
    @State var address: String = ""
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Background()
            view
            addAddressButton
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("addressBook", comment: ""))
        .toolbar {
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                NavigationBackButton()
            }
            ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                navigationButton
            }
        }
        .onDisappear {
            toggleEdit()
        }
    }
    
    var view: some View {
        ScrollView {
            VStack(spacing: 24) {
                ForEach(addressBookViewModel.savedAddresses, id: \.id) { address in
                    AddressBookCell(address: address)
                }
            }
            .padding(15)
            .padding(.top, 10)
        }
    }
    
    var navigationButton: some View {
        Button {
            toggleEdit()
        } label: {
            navigationEditButton
        }
    }
    
    var navigationEditButton: some View {
        ZStack {
            if addressBookViewModel.isEditing {
                doneButton
            } else {
                NavigationEditButton()
            }
        }
    }
    
    var doneButton: some View {
        Text(NSLocalizedString("done", comment: ""))
#if os(iOS)
            .font(.body18MenloBold)
            .foregroundColor(.neutral0)
#elseif os(macOS)
            .font(.body18Menlo)
#endif
    }
    
    var addAddressButton: some View {
        NavigationLink {
            AddAddressBookView(vault: vault)
        } label: {
            FilledButton(title: "addAddress")
                .padding(.horizontal, 16)
                .padding(.vertical, 40)
        }
        .frame(height: addressBookViewModel.isEditing ? nil : 0)
        .animation(.easeInOut, value: addressBookViewModel.isEditing)
        .clipped()
    }
    
    private func toggleEdit() {
        withAnimation {
            addressBookViewModel.isEditing.toggle()
        }
    }
}

#Preview {
    AddressBookView(vault: Vault.example)
        .environmentObject(AddressBookViewModel())
        .environmentObject(CoinSelectionViewModel())
}
