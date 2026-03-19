import Foundation

struct SendAddressResolver {

    /// Resolves a human-readable alias for a destination address.
    /// Priority: vault name > address book title > ENS/name service label
    static func resolveAlias(
        address: String,
        coinMeta: CoinMeta,
        ensLabel: String?,
        vaults: [Vault],
        addressBookItems: [AddressBookItem]
    ) -> String? {
        let lowered = address.lowercased()

        // 1. Own vault match
        let vaultName = vaults.first { vault in
            vault.coins.contains { coin in
                coin.chain == coinMeta.chain &&
                coin.address.lowercased() == lowered
            }
        }?.name
        if let vaultName { return vaultName }

        // 2. Address book match
        let chainType = AddressBookChainType(coinMeta: coinMeta)
        let bookTitle = addressBookItems.first { item in
            AddressBookChainType(coinMeta: item.coinMeta) == chainType &&
            item.address.lowercased() == lowered
        }?.title
        if let bookTitle { return bookTitle }

        // 3. ENS/TNS resolved name
        return ensLabel
    }
}
