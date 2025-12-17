//
//  SettingsRoute.swift
//  VultisigApp
//
//  Created by Assistant on 2025-12-16.
//

import SwiftUI

enum SettingsRoute: Hashable {
    case vaultSettings(vault: Vault)
    case vultDiscountTiers(vault: Vault)
    case registerVaults(vault: Vault)
    case language
    case currency
    case addressBook
    case addAddressBook(address: String? = nil, chain: AddressBookChainType? = nil)
    case editAddressBook(addressBookItem: AddressBookItem)
    case faq
    case checkForUpdates
    case advancedSettings
    case vaultDetailQRCode(vault: Vault)
    case referralOnboarding(referredViewModel: StateWrapper<ReferredViewModel>)
    case referrals(referralViewModel: StateWrapper<ReferralViewModel>, referredViewModel: StateWrapper<ReferredViewModel>)
}

// Wrapper for @StateObject to make it Hashable
struct StateWrapper<T: ObservableObject>: Hashable {
    let id: UUID = UUID()
    let object: T

    static func == (lhs: StateWrapper<T>, rhs: StateWrapper<T>) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
