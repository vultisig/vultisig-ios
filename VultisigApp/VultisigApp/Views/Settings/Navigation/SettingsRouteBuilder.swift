//
//  SettingsRouteBuilder.swift
//  VultisigApp
//
//  Created by Assistant on 2025-12-16.
//

import SwiftUI

struct SettingsRouteBuilder {
    @ViewBuilder
    func buildMainSettingsScreen(vault: Vault) -> some View {
        SettingsMainScreen(vault: vault)
    }
    
    @ViewBuilder
    func buildVaultSettingsScreen(vault: Vault) -> some View {
        VaultSettingsScreen(vault: vault)
    }

    @ViewBuilder
    func buildVultDiscountTiersScreen(vault: Vault) -> some View {
        VultDiscountTiersScreen(vault: vault)
    }

    @ViewBuilder
    func buildRegisterVaultsScreen(vault: Vault) -> some View {
        RegisterVaultView(vault: vault)
    }

    @ViewBuilder
    func buildLanguageScreen() -> some View {
        SettingsLanguageSelectionView()
    }

    @ViewBuilder
    func buildCurrencyScreen() -> some View {
        SettingsCurrencySelectionView()
    }

    @ViewBuilder
    func buildAddressBookScreen() -> some View {
        AddressBookView(
            shouldReturnAddress: false,
            returnAddress: .constant("")
        )
    }

    @ViewBuilder
    func buildAddAddressBookScreen(address: String?, chain: AddressBookChainType?) -> some View {
        AddAddressBookScreen(address: address, chain: chain)
    }

    @ViewBuilder
    func buildEditAddressBookScreen(addressBookItem: AddressBookItem) -> some View {
        EditAddressBookScreen(addressBookItem: addressBookItem)
    }

    @ViewBuilder
    func buildFAQScreen() -> some View {
        SettingsFAQView()
    }

    @ViewBuilder
    func buildCheckForUpdatesScreen() -> some View {
        PhoneCheckUpdateView()
    }

    @ViewBuilder
    func buildAdvancedSettingsScreen() -> some View {
        SettingsAdvancedView()
    }

    @ViewBuilder
    func buildVaultDetailQRCodeScreen(vault: Vault) -> some View {
        VaultDetailQRCodeView(vault: vault)
    }
}
