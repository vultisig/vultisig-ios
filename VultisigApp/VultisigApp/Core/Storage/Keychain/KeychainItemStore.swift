//
//  KeychainItemStore.swift
//  VultisigApp
//

import Foundation
import Security

/// The four `SecItem` calls `Keychain` makes, behind a seam.
///
/// The seam exists so the write path can be tested. A unit-test bundle has no
/// keychain entitlement — every real `SecItem` call returns
/// `errSecMissingEntitlement` — so without this the branch that decides between
/// updating an item in place and adding a new one would ship unverified, and
/// that branch is what keeps a failed write from destroying the previous value.
protocol KeychainItemStore {
    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, data: Data?)
    func add(_ attributes: [String: Any]) -> OSStatus
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}

struct SecItemStore: KeychainItemStore {

    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, data: Data?) {
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        return (status, dataTypeRef as? Data)
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}
