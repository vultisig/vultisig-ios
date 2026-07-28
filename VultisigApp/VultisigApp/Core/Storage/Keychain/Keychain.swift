//
//  Keychain.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 14.10.2024.
//

import Foundation
import OSLog
import Security

private let logger = Log.app.store

struct Keychain {

    private let serviceName: String
    private let itemStore: KeychainItemStore

    private let kSecClassGenericPasswordValue = String(kSecClassGenericPassword)
    private let kSecClassValue = String(kSecClass)
    private let kSecAttrServiceValue = String(kSecAttrService)
    private let kSecValueDataValue = String(kSecValueData)
    private let kSecMatchLimitValue = String(kSecMatchLimit)
    private let kSecReturnDataValue = String(kSecReturnData)
    private let kSecMatchLimitOneValue = String(kSecMatchLimitOne)
    private let kSecAttrAccountValue = String(kSecAttrAccount)
    private let kSecAttrAccessibleValue = String(kSecAttrAccessible)

    init(serviceName: String, itemStore: KeychainItemStore = SecItemStore()) {
        self.serviceName = serviceName
        self.itemStore = itemStore
    }

    // MARK: - String

    func getString(for key: KeychainIdentifier) -> String? {
        guard let data = get(for: key),
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    func setString(_ value: String?, for key: KeychainIdentifier) {
        let data = value?.data(using: .utf8)
        set(data, for: key)
    }

    // MARK: - Int

    func getInt(for key: KeychainIdentifier) -> Int? {
        guard let string = getString(for: key),
              let value = Int(string) else {
            return nil
        }
        return value
    }

    func setInt(_ value: Int?, for key: KeychainIdentifier) {
        let string = value.map { String($0) }
        setString(string, for: key)
    }

    // MARK: - Data

    func getData(for key: KeychainIdentifier) -> Data? {
        return get(for: key)
    }

    /// - Parameter accessibility: the item's `kSecAttrAccessible` class. Defaults
    ///   to the app-wide `WhenUnlockedThisDeviceOnly`; key material that has to
    ///   survive a device migration overrides it, since a `ThisDeviceOnly` item
    ///   is absent from every backup and would leave a restored device unable to
    ///   open its own vaults.
    @discardableResult
    func setData(
        _ value: Data?,
        for key: KeychainIdentifier,
        accessibility: CFString = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    ) -> Bool {
        set(value, for: key, accessibility: accessibility)
    }

    // MARK: - Helpers

    @discardableResult
    func delete(for key: KeychainIdentifier) -> Bool {
        let query = generateQuery(for: key)
        let status = itemStore.delete(query)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("Keychain delete failed for \(key.identifier, privacy: .public): status=\(status, privacy: .public)")
            return false
        }
        return true
    }

}

// MARK: - Privates

private extension Keychain {

    /// Writes an item, updating in place when one already exists.
    ///
    /// Deliberately not delete-then-add: that destroys the stored value before
    /// the replacement is known to have landed, so a failing write loses the old
    /// value as well as the new one. Harmless for a re-enterable password, fatal
    /// for the key that opens the vault key shares — losing it during a passcode
    /// change would leave every share encrypted under a key that no longer
    /// exists.
    ///
    /// - Returns: whether the value is stored. Callers holding key material are
    ///   expected to verify by reading back; the return value and the log entry
    ///   are so a failure is never silent.
    @discardableResult
    func set(
        _ data: Data?,
        for key: KeychainIdentifier,
        accessibility: CFString = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    ) -> Bool {

        guard let data = data else {
            return delete(for: key)
        }

        var query = generateQuery(for: key)
        query.removeValue(forKey: kSecReturnDataValue)

        let attributes: [String: Any] = [
            kSecValueDataValue: data,
            kSecAttrAccessibleValue: accessibility
        ]

        let updateStatus = itemStore.update(query, attributes: attributes)
        if updateStatus == errSecSuccess {
            return true
        }
        guard updateStatus == errSecItemNotFound else {
            logger.error("Keychain update failed for \(key.identifier, privacy: .public): status=\(updateStatus, privacy: .public)")
            return false
        }

        query.updateValue(data, forKey: kSecValueDataValue)
        query.updateValue(accessibility, forKey: kSecAttrAccessibleValue)

        let addStatus = itemStore.add(query)
        guard addStatus == errSecSuccess else {
            logger.error("Keychain add failed for \(key.identifier, privacy: .public): status=\(addStatus, privacy: .public)")
            return false
        }
        return true
    }

    func get(for key: KeychainIdentifier) -> Data? {

        let query = generateQuery(for: key)

        let (status, data) = itemStore.copyMatching(query)

        guard status == errSecSuccess, let data else {
            return nil
        }

        return data
    }

    func generateQuery(for key: KeychainIdentifier) -> [String: Any] {
        return [
            kSecClassValue: kSecClassGenericPasswordValue,
            kSecAttrServiceValue: serviceName,
            kSecAttrAccountValue: key.identifier,
            kSecReturnDataValue: kCFBooleanTrue as Any
        ]
    }
}
