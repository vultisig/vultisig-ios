//
//  Keychain.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 14.10.2024.
//

import Foundation
import Security

struct Keychain {

    private let serviceName: String

    private let kSecClassGenericPasswordValue = String(kSecClassGenericPassword)
    private let kSecClassValue = String(kSecClass)
    private let kSecAttrServiceValue = String(kSecAttrService)
    private let kSecValueDataValue = String(kSecValueData)
    private let kSecMatchLimitValue = String(kSecMatchLimit)
    private let kSecReturnDataValue = String(kSecReturnData)
    private let kSecMatchLimitOneValue = String(kSecMatchLimitOne)
    private let kSecAttrAccountValue = String(kSecAttrAccount)
    private let kSecAttrAccessibleValue = String(kSecAttrAccessible)

    init(serviceName: String) {
        self.serviceName = serviceName
    }

    // MARK: - Data

    func getData(key: KeychainIdentifier) -> Data? {
        return get(for: key)
    }

    func setData(_ value: Data?, for key: KeychainIdentifier) {
        set(value, for: key)
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

    // MARK: - Bool

    func getBool(for key: KeychainIdentifier) -> Bool {
        guard getString(for: key) != nil else {
            return false
        }
        return true
    }

    func setBool(_ value: Bool, for key: KeychainIdentifier) {
        setString(value ? "true" : nil, for: key)
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

    func getObject<T: Codable>(key: KeychainIdentifier) -> T? {
        guard let data = get(for: key) else {
            return nil
        }
        let object = try? JSONDecoder().decode(T.self, from: data)
        return object
    }

    func setObject<T: Codable>(_ object: T, for key: KeychainIdentifier) {
        let data = try? JSONEncoder().encode(object)
        set(data, for: key)
    }

    // MARK: - Helpers

    func exist(_ key: KeychainIdentifier) -> Bool {
        return get(for: key) != nil
    }

    func delete(for key: KeychainIdentifier) {
        let query = generateQuery(for: key)
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Cleanup

    func cleanup() {
        let dictionary = [kSecClass as String: kSecClassGenericPasswordValue]
        SecItemDelete(dictionary as CFDictionary)
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

        SecItemDelete(query as CFDictionary)

        query.removeValue(forKey: kSecReturnDataValue)
        query.updateValue(data, forKey: kSecValueDataValue)
        query.updateValue(kSecAttrAccessibleWhenUnlockedThisDeviceOnly, forKey: kSecAttrAccessibleValue)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            return
        }
    }

    func get(for key: KeychainIdentifier) -> Data? {

        let query = generateQuery(for: key)

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        guard status == errSecSuccess, let data = dataTypeRef as? Data else {
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
