//
//  AddressBookView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-10.
//

import SwiftUI
import SwiftData

struct AddressBookView: View {
    @Environment(\.router) var router
    var shouldReturnAddress = true
    @Binding var returnAddress: String

    @Query var savedAddresses: [AddressBookItem]

    @State var title: String = ""
    @State var address: String = ""
    @State var isEditing = false
    @State var coin: Coin?

    @Environment(\.modelContext) var modelContext

    var savedAddressesEmpty: Bool { savedAddresses.isEmpty }

    var body: some View {
        Screen(showNavigationBar: false, edgeInsets: ScreenEdgeInsets(bottom: savedAddressesEmpty ? nil : 0)) {
            VStack {
                Group {
                    if savedAddressesEmpty {
                       emptyView
                            .background(BlurredBackground())
                    } else {
                        list
                        addAddressButton
                            .padding(.bottom, 12)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .crossPlatformToolbar("addressBook".localized) {
            CustomToolbarItem(placement: .trailing) {
                navigationButton
                    .showIf(!savedAddressesEmpty)
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
                .multilineTextAlignment(.center)
            Text("addressBookEmptySubtitle".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textTertiary)
                .multilineTextAlignment(.center)

            addAddressButton
                .frame(maxWidth: 200)
                .padding(.top, 18)
        }
        .frame(maxWidth: 265)
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
                        .listRowBackground(Color.clear)
                    }
                    .onMove(perform: isEditing ? move: nil)
                }
                .listStyle(.plain)
                .buttonStyle(.borderless)
                .colorScheme(.dark)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            } else {
                emptyViewChain
            }
        }
    }

    var addAddressButton: some View {
        PrimaryButton(title: "addAddress".localized) {
            router.navigate(to: SettingsRoute.addAddressBook())
        }
    }

    var emptyViewChain: some View {
        VStack {
            Spacer()
            ErrorMessage(text: "noSavedAddressesForChain")
            Spacer()
        }
    }

    @ViewBuilder
    var navigationButton: some View {
        if isEditing {
            Button { toggleEdit() } label: {
                NavigationBarButtonView(title: "done".localized)
            }
        } else {
            ToolbarButton(image: "pencil") {
                toggleEdit()
            }
        }
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
