//
//  SettingsRoute.swift
//  VultisigApp
//
//  Created by Assistant on 2025-12-16.
//

import SwiftUI

enum SettingsRoute: Hashable {
    case main(vault: Vault)
    case vaultSettings(vault: Vault)
    case vultDiscountTiers(vault: Vault)
    case language
    case currency
    case addressBook
    case addAddressBook(address: String? = nil, chain: AddressBookChainType? = nil)
    case editAddressBook(addressBookItem: AddressBookItem)
    case notifications
    case faq
    case checkForUpdates
    case advancedSettings
    case vaultDetailQRCode(vault: Vault)
}
