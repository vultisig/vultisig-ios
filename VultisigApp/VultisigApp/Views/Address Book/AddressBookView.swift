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
    
    var body: some View {
        Screen(title: "addressBook".localized) {
            VStack {
                Group {
                    if savedAddresses.isEmpty {
                       emptyView
                    } else {
                        list
                        addAddressButton
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(BlurredBackground())
        }
        .screenToolbar {
            if savedAddresses.count != 0 {
                navigationButton
            }
        }
        .onDisappear {
            withAnimation {
                isEditing = false
            }
        }
    }
    
    var emptyView: some View {
        VStack(spacing: 12) {
            Text("addressBookEmptyTitle".localized)
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textPrimary)
            Text("addressBookEmptySubtitle".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textExtraLight)
            
            addAddressButton
                .frame(maxWidth: 200)
                .padding(.top, 18)
        }
    }
    
    var list: some View {
        let filteredAddress = savedAddresses.filter {
            coin == nil || (coin != nil && $0.coinMeta.chain.chainType == coin?.chainType)
        }
        
        return ZStack {
            if filteredAddress.count > 0 {
                List {
                    ForEach(filteredAddress.sorted(by: {
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
                    .padding(.horizontal, 15)
                    .background(Theme.colors.bgPrimary)
                }
                .listStyle(PlainListStyle())
                .buttonStyle(BorderlessButtonStyle())
                .colorScheme(.dark)
                .scrollContentBackground(.hidden)
                .padding(.top, 30)
                .background(Theme.colors.bgPrimary.opacity(0.9))
            } else {
                emptyViewChain
            }
        }
    }
    
    var addAddressButton: some View {
        PrimaryNavigationButton(title: "addAddress") {
            AddAddressBookView(count: savedAddresses.count, coin: coin?.toCoinMeta())
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
            .font(Theme.fonts.bodyLMedium)
            .foregroundColor(Theme.colors.textPrimary)
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
    
}

#Preview {
    AddressBookView(returnAddress: .constant(""), coin: Coin.example)
        .environmentObject(CoinSelectionViewModel())
        .environmentObject(HomeViewModel())
}
