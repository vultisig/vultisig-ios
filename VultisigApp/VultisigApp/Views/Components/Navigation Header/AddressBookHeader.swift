//
//  AddressBookHeader.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-08.
//

import SwiftUI

struct AddressBookHeader: View {
    let count: Int
    @Binding var isEditing: Bool
    
    var body: some View {
        HStack {
            leadingAction
            Spacer()
            text
            Spacer()
            trailingAction
        }
        .padding(.vertical, 8)
    }
    
    var leadingAction: some View {
        NavigationBackButton()
    }
    
    var text: some View {
        Text(NSLocalizedString("addressBook", comment: ""))
            .foregroundColor(.neutral0)
            .font(.title3)
    }
    
    var trailingAction: some View {
        ZStack {
            if count != 0 {
                navigationButton
            }
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
            if isEditing {
                doneButton
            } else {
                NavigationEditButton()
            }
        }
    }
    
    var doneButton: some View {
        Text(NSLocalizedString("done", comment: ""))
            .foregroundColor(.neutral0)
            .font(.body18Menlo)
    }
    
    private func toggleEdit() {
        withAnimation {
            isEditing.toggle()
        }
    }
}

#Preview {
    func refreshAction() {}
    return AddressBookHeader(count: 0, isEditing: .constant(false))
}
