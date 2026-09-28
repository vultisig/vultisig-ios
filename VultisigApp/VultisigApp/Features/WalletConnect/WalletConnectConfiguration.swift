//
//  WalletConnectConfiguration.swift
//  VultisigApp
//

import Foundation

struct WalletConnectConfiguration: Equatable {
    let projectId: String
    let appName: String
    let appDescription: String
    let appURL: URL
    let appIconURL: URL

    static func fromMainBundle() throws -> WalletConnectConfiguration {
        let projectId = Bundle.main.object(forInfoDictionaryKey: "WalletConnectProjectId") as? String
        return try WalletConnectConfiguration(projectId: projectId)
    }

    init(projectId: String?) throws {
        guard let projectId = projectId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !projectId.isEmpty,
              projectId != "$(WALLETCONNECT_PROJECT_ID)" else {
            throw WalletConnectError.missingProjectId
        }

        self.projectId = projectId
        self.appName = "Vultisig"
        self.appDescription = "Vultisig Wallet"
        self.appURL = URL(string: "https://vultisig.com")!
        self.appIconURL = URL(string: "https://vultisig.com/favicon.ico")!
    }
}
