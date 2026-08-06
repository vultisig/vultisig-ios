//
//  KeychainItemStore.swift
//  VultisigApp
//

import Foundation
import Security

/// The `SecItem` calls ``Keychain`` makes, behind a seam.
///
/// The seam exists so the read path can be tested. A unit-test bundle has no
/// keychain entitlement, so every real `SecItem` call answers
/// `errSecMissingEntitlement` — one of the very statuses the read path has to
/// tell apart from "no such item", and one it cannot be shown to tell apart if
/// it is the only status a test can ever produce.
protocol KeychainItemStore {
    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, data: Data?)
    func add(_ attributes: [String: Any]) -> OSStatus
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

    func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}
