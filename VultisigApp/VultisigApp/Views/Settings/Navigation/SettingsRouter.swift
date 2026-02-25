//
//  SettingsRouter.swift
//  VultisigApp
//
//  Created by Assistant on 2025-12-16.
//

import SwiftUI

struct SettingsRouter {
    private let viewBuilder = SettingsRouteBuilder()

    @ViewBuilder
    func build(_ route: SettingsRoute) -> some View {
        switch route {
        case .main(let vault):
            viewBuilder.buildMainSettingsScreen(vault: vault)
        case .vaultSettings(let vault):
            viewBuilder.buildVaultSettingsScreen(vault: vault)
        case .vultDiscountTiers(let vault):
            viewBuilder.buildVultDiscountTiersScreen(vault: vault)
        case .registerVaults(let vault):
            viewBuilder.buildRegisterVaultsScreen(vault: vault)
        case .language:
            viewBuilder.buildLanguageScreen()
        case .currency:
            viewBuilder.buildCurrencyScreen()
        case .notifications:
            viewBuilder.buildNotificationsScreen()
        case .addressBook:
            viewBuilder.buildAddressBookScreen()
        case .addAddressBook(let address, let chain):
            viewBuilder.buildAddAddressBookScreen(address: address, chain: chain)
        case .editAddressBook(let addressBookItem):
            viewBuilder.buildEditAddressBookScreen(addressBookItem: addressBookItem)
        case .faq:
            viewBuilder.buildFAQScreen()
        case .checkForUpdates:
            viewBuilder.buildCheckForUpdatesScreen()
        case .advancedSettings:
            viewBuilder.buildAdvancedSettingsScreen()
        case .vaultDetailQRCode(let vault):
            viewBuilder.buildVaultDetailQRCodeScreen(vault: vault)
        }
    }
}
