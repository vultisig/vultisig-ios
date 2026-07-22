//
//  MockKeychainService.swift
//  VultisigAppTests
//

import Foundation
@testable import VultisigApp

/// In-memory `KeychainService` so migration-ordering behaviour can be driven
/// without touching the real Keychain (which persists across test runs and
/// across app reinstalls).
final class MockKeychainService: KeychainService {
    var lastMigratedVersion: Int?

    private var fastPasswords: [String: String] = [:]
    private var fastHints: [String: String] = [:]
    private var deviceToken: String?

    init(lastMigratedVersion: Int? = nil) {
        self.lastMigratedVersion = lastMigratedVersion
    }

    func getFastPassword(pubKeyECDSA: String) -> String? { fastPasswords[pubKeyECDSA] }

    func setFastPassword(_ fastPassword: String?, pubKeyECDSA: String) {
        fastPasswords[pubKeyECDSA] = fastPassword
    }

    func getFastHint(pubKeyECDSA: String) -> String? { fastHints[pubKeyECDSA] }

    func setFastHint(_ fastHint: String?, pubKeyECDSA: String) {
        fastHints[pubKeyECDSA] = fastHint
    }

    func getLastMigratedVersion() -> Int? { lastMigratedVersion }

    func setLastMigratedVersion(_ version: Int?) { lastMigratedVersion = version }

    func getDeviceToken() -> String? { deviceToken }

    func setDeviceToken(_ token: String?) { deviceToken = token }
}
