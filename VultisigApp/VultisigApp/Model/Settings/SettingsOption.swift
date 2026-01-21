//
//  SettingsOption.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 19/08/2025.
//

import Foundation

struct SettingsOptionGroup: Identifiable {
    var id: String { title }
    let title: String
    let options: [SettingsOption]
}

enum SettingsOptionType {
    case navigation
    case button
    case link(url: URL)
    case shareLink(url: URL)
}

enum SettingsOption: String, Identifiable {
    var id: String { rawValue }

    case vaultSettings
    case vultDiscountTiers
    case registerVaults
    case language
    case currency
    case addressBook
    case referralCode
    case faq
    case education
    case checkForUpdates
    case shareApp
    case twitter
    case discord
    case github
    case website
    case privacyPolicy
    case termsOfService

    var title: String {
        switch self {
        case .vaultSettings:
            return "vaultSettings"
        case .vultDiscountTiers:
            return "vultDiscountTiers"
        case .registerVaults:
            return "registerYourVaults"
        case .language:
            return "language"
        case .currency:
            return "currency"
        case .addressBook:
            return "addressBook"
        case .referralCode:
            return "referralCode"
        case .faq:
            return "faq"
        case .education:
            return "vultisigEducation"
        case .checkForUpdates:
            return "checkForUpdates"
        case .shareApp:
            return "shareTheApp"
        case .twitter:
            return "x"
        case .discord:
            return "discord"
        case .github:
            return "github"
        case .website:
            return "vultisigWebsite"
        case .privacyPolicy:
            return "privacyPolicy"
        case .termsOfService:
            return "termsOfService"
        }
    }

    var icon: String? {
        switch self {
        case .vaultSettings:
            return "settings"
        case .vultDiscountTiers:
            return "coins"
        case .registerVaults:
            return "logo-outline"
        case .language:
            return "languages"
        case .currency:
            return "circle-dollar-sign"
        case .addressBook:
            return "book-marked"
        case .referralCode:
            return "megaphone"
        case .faq:
            return "message-circle-question"
        case .education:
            return nil
        case .checkForUpdates:
            return "cloud-upload"
        case .shareApp:
            return "share-2"
        case .twitter:
            return "twitter"
        case .discord:
            return "discord"
        case .github:
            return "github"
        case .website:
            return "globe"
        case .privacyPolicy:
            return "secure"
        case .termsOfService:
            return "notebook-text"
        }
    }

    var type: SettingsOptionType {
        switch self {
        case .twitter:
            return .link(url: StaticURL.XVultisigURL)
        case .discord:
            return .link(url: StaticURL.DiscordVultisigURL)
        case .website:
            return .link(url: StaticURL.VultisigWebsiteURL)
        case .github:
            return .link(url: StaticURL.GithubVultisigURL)
        case .shareApp:
            return .shareLink(url: StaticURL.AppStoreVultisigURL)
        case .privacyPolicy:
            return .link(url: StaticURL.PrivacyPolicyURL)
        case .termsOfService:
            return .link(url: StaticURL.TermsOfServiceURL)
        case .referralCode:
            return .button
        default:
            return .navigation
        }
    }
}
