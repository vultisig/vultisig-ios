//
//  URL.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-05.
//

import Foundation

class StaticURL {
    static let GithubVultisigURL = URL(string: "https://github.com/vultisig/vultisig-ios")!
    static let XVultisigURL = URL(string: "https://x.com/vultisig")!
    static let AppStoreVultisigURL = URL(string: "https://apps.apple.com/app/vultisig/id6503023896")!
    static let DiscordVultisigURL = URL(string: "https://discord.gg/ngvW8tRRfB")!
    static let PrivacyPolicyURL = URL(string: "https://vultisig.com/privacy")!
    static let TermsOfServiceURL = URL(string: "https://vultisig.com/termofservice")!
    static let VultisigAirdropWeb = URL(string: "https://airdrop.vultisig.com/")!
    static let VultisigWebsiteURL = URL(string: "https://vultisig.com")!
    static let VultisigVultURL = URL(string: "https://vultisig.com/vult")!
    static let VultBackupURL = URL(string: "https://docs.vultisig.com/vultisig-app-actions/managing-your-vault/vault-backup")!
    static let GitHubReleasesURL: URL = {
        guard let url = URL(string: "https://github.com/vultisig/vultisig-ios/releases") else {
            preconditionFailure("Invalid GitHubReleasesURL")
        }
        return url
    }()
}
