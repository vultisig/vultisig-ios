//
//  AddAddressBookView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-11.
//

import SwiftUI

struct AddAddressBookView: View {
    @State var title = ""
    @State var address = ""
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("addAddress", comment: ""))
        .toolbar {
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                NavigationBackButton()
            }
        }
    }
    
    var view: some View {
        VStack(spacing: 22) {
            titleField
            addressField
        }
    }
    
    var titleField: some View {
        AddressBookTextField(title: "title", text: $title)
    }
    
    var addressField: some View {
        AddressBookTextField(title: "address", text: $address)
    }
}

#Preview {
    AddAddressBookView()
}
