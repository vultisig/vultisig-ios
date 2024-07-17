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
    
    @EnvironmentObject var coinSelectionViewModel: CoinSelectionViewModel
    
    @State var title: String = ""
    @State var address: String = ""
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
            
            if savedAddresses.count != 0 {
                ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                    navigationButton
                }
            }
        }
        .onDisappear {
            withAnimation {
                isEditing = false
            }
        }
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
    
    var list: some View {
        List {
            ForEach(savedAddresses.sorted(by: {
                $0.order < $1.order
            }), id: \.id) { address in
                AddressBookCell(
                    address: address,
                    shouldReturnAddress: shouldReturnAddress, 
                    isEditing: isEditing,
                    returnAddress: $returnAddress
                )
            }
            .onMove(perform: isEditing ? move: nil)
            .background(Color.backgroundBlue)
        }
        .listStyle(PlainListStyle())
        .buttonStyle(BorderlessButtonStyle())
        .colorScheme(.dark)
        .scrollContentBackground(.hidden)
        .padding(15)
        .padding(.top, 10)
        .background(Color.backgroundBlue)
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
#if os(iOS)
            .font(.body18MenloBold)
            .foregroundColor(.neutral0)
#elseif os(macOS)
            .font(.body18Menlo)
#endif
    }
    
    var addAddressButton: some View {
        let condition = isEditing || savedAddresses.count == 0
        
        return NavigationLink {
            AddAddressBookView(count: savedAddresses.count)
        } label: {
            FilledButton(title: "addAddress")
                .padding(.horizontal, 16)
                .padding(.vertical, 40)
        }
        .frame(height: condition ? nil : 0)
        .animation(.easeInOut, value: isEditing)
        .clipped()
    }
    
    private func toggleEdit() {
        withAnimation {
            isEditing.toggle()
        }
    }
    
    private func move(from: IndexSet, to: Int) {
        let fromIndex = from.first ?? 0
        
        if fromIndex<to {
            moveDown(fromIndex: fromIndex, toIndex: to-1)
        } else {
            moveUp(fromIndex: fromIndex, toIndex: to)
        }
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
    AddressBookView(returnAddress: .constant(""))
        .environmentObject(CoinSelectionViewModel())
        .environmentObject(HomeViewModel())
}
