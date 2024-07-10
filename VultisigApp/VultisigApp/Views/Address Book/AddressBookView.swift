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
        ZStack {
            Background()
            view
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
                NavigationAddButton()
            } else {
                NavigationEditButton()
            }
        }
    }
}

#Preview {
    AddressBookView()
}
