//
//  ЛунсрфштЫукмшсу.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 14.10.2024.
//

import Foundation

protocol KeychainService: AnyObject {
    func getFastPassword(pubKeyECDSA: String) -> String?
    func setFastPassword(_ fastPassword: String?, pubKeyECDSA: String)
    func getFastHint(pubKeyECDSA: String) -> String?
    func setFastHint(_ fastHint: String?, pubKeyECDSA: String)
    func getLastMigratedVersion() -> Int?
    func setLastMigratedVersion(_ version: Int?)
    func getDeviceToken() -> String?
    func setDeviceToken(_ token: String?)
}

final class DefaultKeychainService: KeychainService {

    private static let serviceName = "com.vultisig.wallet"

    static let shared: KeychainService = {
        let keychain = Keychain(serviceName: serviceName)
        return DefaultKeychainService(keychain: keychain)
    }()

    private let keychain: Keychain

    init(keychain: Keychain) {
        self.keychain = keychain
    }

    func getFastPassword(pubKeyECDSA: String) -> String? {
        return keychain.getString(for: Keys.fastPassword(pubKeyECDSA: pubKeyECDSA))
    }

    func setFastPassword(_ fastPassword: String?, pubKeyECDSA: String) {
        keychain.setString(fastPassword, for: Keys.fastPassword(pubKeyECDSA: pubKeyECDSA))
    }

    func getFastHint(pubKeyECDSA: String) -> String? {
        return keychain.getString(for: Keys.fastHint(pubKeyECDSA: pubKeyECDSA))
    }

    func setFastHint(_ fastHint: String?, pubKeyECDSA: String) {
        keychain.setString(fastHint, for: Keys.fastHint(pubKeyECDSA: pubKeyECDSA))
    }

    func getLastMigratedVersion() -> Int? {
        return keychain.getInt(for: Keys.lastMigratedVersion)
    }

    func setLastMigratedVersion(_ version: Int?) {
        keychain.setInt(version, for: Keys.lastMigratedVersion)
    }

    func getDeviceToken() -> String? {
        return keychain.getString(for: Keys.deviceToken)
    }

    func setDeviceToken(_ token: String?) {
        keychain.setString(token, for: Keys.deviceToken)
    }
}

private extension DefaultKeychainService {

    enum Keys: KeychainIdentifier {
        case fastPassword(pubKeyECDSA: String)
        case fastHint(pubKeyECDSA: String)
        case lastMigratedVersion
        case deviceToken

        var identifier: String {
            return "\(DefaultKeychainService.serviceName).\(key)"
        }

        private var key: String {
            switch self {
            case .fastPassword(let pubKeyECDSA):
                return "fastPassword-\(pubKeyECDSA)"
            case .fastHint(let pubKeyECDSA):
                return "fastHint-\(pubKeyECDSA)"
            case .lastMigratedVersion:
                return "lastMigratedVersion"
            case .deviceToken:
                return "deviceToken"
            }
        }
    }
}
