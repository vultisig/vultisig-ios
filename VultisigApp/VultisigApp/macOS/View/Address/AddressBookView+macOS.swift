//
//  AddressBookView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-18.
//

#if os(macOS)
import SwiftUI

extension AddressBookView {
    var content: some View {
        ZStack(alignment: .bottom) {
            Background()
            main
        }
        .onDisappear {
            withAnimation {
                isEditing = false
            }
        }
    }
    
    var main: some View {
        VStack(spacing: 0) {
            headerMac
            view
            addAddressButton
        }
    }
    
    var headerMac: some View {
        AddressBookHeader(
            count: savedAddresses.count,
            isEditing: $isEditing
        )
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
                    .padding(.horizontal, 18)
                    .background(Color.backgroundBlue)
                }
                .listStyle(PlainListStyle())
                .buttonStyle(BorderlessButtonStyle())
                .colorScheme(.dark)
                .scrollContentBackground(.hidden)
                .padding(.top, 30)
                .background(Color.backgroundBlue.opacity(0.9))
            } else {
                emptyViewChain
            }
        }
    }
    
    var addAddressButton: some View {
        NavigationLink {
            AddAddressBookView(count: savedAddresses.count, coin: coin?.toCoinMeta())
        } label: {
            FilledButton(title: "addAddress")
                .padding(.horizontal, 16)
                .padding(.vertical, 30)
                .padding(.horizontal, 24)
        }
        .background(Color.backgroundBlue)
    }
}
#endif
