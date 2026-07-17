//
//  SettingsOption.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 19/08/2025.
//

import Foundation
import SwiftUI

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

enum SettingsOption: String, Identifiable, CaseIterable {
    var id: String { rawValue }

    case vaultSettings
    case vultDiscountTiers
    case language
    case currency
    case notifications
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
        case .language:
            return "language"
        case .currency:
            return "currency"
        case .notifications:
            return "notifications"
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

    var icon: ImageResource? {
        switch self {
        case .vaultSettings:
            return .gear
        case .vultDiscountTiers:
            return .coins
        case .language:
            return .language
        case .currency:
            return .circleDollar
        case .notifications:
            return .bell
        case .addressBook:
            return .bookBookmark
        case .referralCode:
            return .megaphone
        case .faq:
            return .bubbleQuestion
        case .education:
            return .books
        case .checkForUpdates:
            return .cloudUpload
        case .shareApp:
            return .share2
        case .twitter:
            return .twitter
        case .discord:
            return .discord
        case .github:
            return .github
        case .website:
            return .globe
        case .privacyPolicy:
            return .secure
        case .termsOfService:
            return .notebookText
        }
    }

    var accessibilityID: String? {
        switch self {
        case .language: return AccessibilityID.Settings.languageCell
        case .currency: return AccessibilityID.Settings.currencyCell
        case .vaultSettings: return AccessibilityID.Settings.vaultSettingsCell
        case .faq: return AccessibilityID.Settings.faqCell
        default: return nil
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
        case .education:
            return .link(url: StaticURL.VultisigDocsURL)
        case .referralCode:
            return .button
        default:
            return .navigation
        }
    }
}
