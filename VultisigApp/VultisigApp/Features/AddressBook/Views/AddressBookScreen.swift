//
//  AddressBookScreen.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-10.
//

import SwiftUI
import SwiftData

struct AddressBookScreen: View {
    @Environment(\.router) var router
    var shouldReturnAddress = true
    @Binding var returnAddress: String

    @Query var savedAddresses: [AddressBookItem]

    @State var title: String = ""
    @State var address: String = ""
    @State var isEditing = false
    @State var coin: Coin?

    @Environment(\.modelContext) var modelContext

    private static let emptyStateTopInset: CGFloat = 209
    private static let emptyStateGlowOffset: CGFloat = -39.5

    var savedAddressesEmpty: Bool { savedAddresses.isEmpty }

    var body: some View {
        Screen {
            VStack {
                Group {
                    if savedAddressesEmpty {
                       emptyView
                    } else {
                        list
                        addAddressButton(width: .fill)
                            .padding(.bottom, 12)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(savedAddressesEmpty ? SettingsGlowBackground(verticalOffset: Self.emptyStateGlowOffset) : nil)
        }
        .screenTitle((isEditing && !savedAddressesEmpty ? "editAddressBook" : "addressBook").localized)
        .screenEdgeInsets(ScreenEdgeInsets(bottom: savedAddressesEmpty ? nil : 0))
        .screenToolbar {
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
                .settingsText(.buttonRegular)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("addressBookEmptySubtitle".localized)
                .settingsText(.buttonS)
                .foregroundStyle(Theme.colors.textTertiary)
                .multilineTextAlignment(.center)

            addAddressButton(width: .hug)
                .padding(.top, 18)

            Spacer()
        }
        .frame(maxWidth: 265)
        .padding(.top, Self.emptyStateTopInset)
    }

    var list: some View {
        let filteredAddress = savedAddresses.filter {
            coin == nil || (coin != nil && $0.coinMeta.chain.chainType == coin?.chainType)
        }

        return ZStack {
            if !filteredAddress.isEmpty {
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

    func addAddressButton(width: SettingsCTAButtonStyle.Width) -> some View {
        SettingsCTAButton(title: "addAddress", width: width) {
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
            ToolbarButton(image: .check, iconSize: 24, type: .confirmation) {
                toggleEdit()
            }
        } else {
            ToolbarButton(image: .penWritingFilled, iconSize: 24) {
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
    AddressBookScreen(returnAddress: .constant(""), coin: Coin.example)
        .environmentObject(CoinSelectionViewModel())
        .environmentObject(HomeViewModel())
}
