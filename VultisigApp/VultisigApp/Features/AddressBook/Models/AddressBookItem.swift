//
//  AddressBookItem.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-11.
//

import SwiftData
import Foundation

@Model
class AddressBookItem: Equatable {
    var id = UUID()
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

    static func == (lhs: AddressBookItem, rhs: AddressBookItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.address == rhs.address &&
        lhs.coinMeta == rhs.coinMeta
    }

    static let example = AddressBookItem(title: "Online Wallet", address: "123456789", coinMeta: CoinMeta.example, order: 0)
}
