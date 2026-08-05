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

    /// - Returns: ``KeychainReadResult/unavailable(_:)`` with `errSecDecode` when
    ///   an item exists but its bytes are not UTF-8. The item is present, so
    ///   reporting it as absent would invite a caller to overwrite it.
    func getString(for key: KeychainIdentifier) -> KeychainReadResult<String> {
        switch get(for: key) {
        case .absent:
            return .absent
        case .unavailable(let status):
            return .unavailable(status)
        case .present(let data):
            guard let value = String(data: data, encoding: .utf8) else {
                logger.error("Keychain item is not valid UTF-8 for \(key.identifier, privacy: .public)")
                return .unavailable(errSecDecode)
            }
            return .present(value)
        }
    }

    func setString(_ value: String?, for key: KeychainIdentifier) {
        let data = value?.data(using: .utf8)
        set(data, for: key)
    }

    // MARK: - Int

    /// - Returns: ``KeychainReadResult/unavailable(_:)`` with `errSecDecode` when
    ///   an item exists but does not parse as an integer, for the same reason
    ///   ``getString(for:)`` does.
    func getInt(for key: KeychainIdentifier) -> KeychainReadResult<Int> {
        switch getString(for: key) {
        case .absent:
            return .absent
        case .unavailable(let status):
            return .unavailable(status)
        case .present(let string):
            guard let value = Int(string) else {
                logger.error("Keychain item is not an integer for \(key.identifier, privacy: .public)")
                return .unavailable(errSecDecode)
            }
            return .present(value)
        }
    }

    func setInt(_ value: Int?, for key: KeychainIdentifier) {
        let string = value.map { String($0) }
        setString(string, for: key)
    }

    // MARK: - Helpers

    func delete(for key: KeychainIdentifier) {
        let query = generateQuery(for: key)
        _ = itemStore.delete(query)
    }

}

// MARK: - Privates

private extension Keychain {

    func set(_ data: Data?, for key: KeychainIdentifier) {

        guard let data = data else {
            delete(for: key)
            return
        }

        var query = generateQuery(for: key)

        _ = itemStore.delete(query)

        query.removeValue(forKey: kSecReturnDataValue)
        query.updateValue(data, forKey: kSecValueDataValue)
        query.updateValue(kSecAttrAccessibleWhenUnlockedThisDeviceOnly, forKey: kSecAttrAccessibleValue)

        let status = itemStore.add(query)
        guard status == errSecSuccess else {
            return
        }
    }

    /// Reads one item, keeping apart the three outcomes the Security framework
    /// actually reports.
    ///
    /// Only `errSecItemNotFound` means the key has no item. Every other failing
    /// status means the answer is unknown — the device is locked, the process
    /// lacks the entitlement, the keychain is unusable — and is reported as
    /// ``KeychainReadResult/unavailable(_:)`` so a caller can never mistake a
    /// failed read for permission to write.
    func get(for key: KeychainIdentifier) -> KeychainReadResult<Data> {

        let query = generateQuery(for: key)

        let (status, data) = itemStore.copyMatching(query)

        switch status {
        case errSecSuccess:
            guard let data else {
                logger.error("Keychain returned success with no data for \(key.identifier, privacy: .public)")
                return .unavailable(errSecDecode)
            }
            return .present(data)
        case errSecItemNotFound:
            return .absent
        default:
            logger.error("Keychain read failed for \(key.identifier, privacy: .public): status=\(status, privacy: .public)")
            return .unavailable(status)
        }
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
