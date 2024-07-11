//
//  AddressBookView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-10.
//

import SwiftUI

struct AddressBookView: View {
    @State var isEditing = false
    
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
    }
    
    var view: some View {
        VStack {
            
        }
    }
    
    var navigationButton: some View {
        Button {
            isEditing.toggle()
        } label: {
            navigationEditButton
        }
    }
    
    var navigationEditButton: some View {
        ZStack {
            if isEditing {
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
            AddAddressBookView()
        } label: {
            FilledButton(title: "addAddress")
                .padding(.horizontal, 16)
                .padding(.vertical, 40)
        }
        .frame(height: isEditing ? nil : 0)
        .animation(.easeInOut, value: isEditing)
        .clipped()
    }
}

#Preview {
    AddressBookView()
}
