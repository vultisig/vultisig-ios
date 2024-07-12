//
//  AddressBookViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-11.
//

import Foundation

class AddressBookViewModel: ObservableObject {
    @Published var isEditing = false
    @Published var savedAddresses: [AddressBookItem] = []
    
    func addNewAddress(title: String, address: String, coinMeta: CoinMeta) {
        let newAddress = AddressBookItem(title: title, address: address, coinMeta: coinMeta, order: savedAddresses.count)
        savedAddresses.append(newAddress)
    }
    
    func removeAddress(_ address: AddressBookItem) {
        let index = savedAddresses.firstIndex(of: address)
        
        guard let index else {
            return
        }
        
        savedAddresses.remove(at: index)
    }
}
