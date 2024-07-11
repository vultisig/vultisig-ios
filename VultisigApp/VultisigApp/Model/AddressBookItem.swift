//
//  AddressBookItem.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-11.
//

import Foundation

class AddressBookItem {
    let id = UUID()
    var title: String
    var address: String
    var coinMeta: CoinMeta
    var order: Int
    
    init(title: String, address: String, coinMeta: CoinMeta, order: Int) {
        self.title = title
        self.address = address
        self.coinMeta = coinMeta
        self.order = order
    }
}
