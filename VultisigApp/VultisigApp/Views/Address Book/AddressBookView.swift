//
//  AddressBookView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-10.
//

import SwiftUI
import SwiftData

struct AddressBookView: View {
    var shouldReturnAddress = true
    @Binding var returnAddress: String
    
    @Query var savedAddresses: [AddressBookItem]
    
    @State var title: String = ""
    @State var address: String = ""
    @State var isEditing = false
    @State var coin: Coin?
    
    @Environment(\.modelContext) var modelContext
    @EnvironmentObject var coinSelectionViewModel: CoinSelectionViewModel
    
    var body: some View {
        content
    }
    
    var view: some View {
        ZStack {
            if savedAddresses.count == 0 {
                emptyView
            } else {
                list
            }
        }
    }
    
    var emptyView: some View {
        VStack {
            Spacer()
            ErrorMessage(text: "noSavedAddresses")
            Spacer()
        }
    }
    
    var emptyViewChain: some View {
        VStack {
            Spacer()
            ErrorMessage(text: "noSavedAddressesForChain")
            Spacer()
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
            .font(.body18MenloBold)
            .foregroundColor(.neutral0)
    }
    
    private func toggleEdit() {
        withAnimation {
            isEditing.toggle()
        }
    }
    
    func move(from: IndexSet, to: Int) {
        var s = savedAddresses.sorted(by: { $0.order < $1.order })
        s.move(fromOffsets: from, toOffset: to)
        for (index, item) in s.enumerated() {
                item.order = index
        }
        try? self.modelContext.save()
    }
    
    private func moveDown(fromIndex: Int, toIndex: Int) {
        for index in fromIndex...toIndex {
            savedAddresses[index].order = savedAddresses[index].order-1
        }
        savedAddresses[fromIndex].order = toIndex
    }
    
    private func moveUp(fromIndex: Int, toIndex: Int) {
        savedAddresses[fromIndex].order = toIndex
        for index in toIndex...fromIndex {
            savedAddresses[index].order = savedAddresses[index].order+1
        }
    }
}

#Preview {
    AddressBookView(returnAddress: .constant(""), coin: Coin.example)
        .environmentObject(CoinSelectionViewModel())
        .environmentObject(HomeViewModel())
}
