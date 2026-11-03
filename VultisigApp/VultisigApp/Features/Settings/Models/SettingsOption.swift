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
    case link(url: URL)
    case shareLink(url: URL)
}

enum SettingsOption: String, Identifiable {
    var id: String { rawValue }

    case vaultSettings
    case vultDiscountTiers
    case language
    case currency
    case homeDisplay
    case widgetWatchlist
    case notifications
    case addressBook
    case faq
    case education
    case checkForUpdates
    case rateApp
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
        case .homeDisplay:
            return "homeDisplay"
        case .widgetWatchlist:
            return "watchlist"
        case .notifications:
            return "notifications"
        case .addressBook:
            return "addressBook"
        case .faq:
            return "faq"
        case .education:
            return "vultisigEducation"
        case .checkForUpdates:
            return "checkForUpdates"
        case .rateApp:
            return "rateTheApp"
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
            return .slider
        case .vultDiscountTiers:
            return .cardsFilled
        case .language:
            return .language
        case .currency:
            return .circleDollar
        case .homeDisplay:
            return .walletFilledSolid
        case .widgetWatchlist:
            return .eye
        case .notifications:
            return .bellFilled
        case .addressBook:
            return .bookBookmarkFilled
        case .faq:
            return .squareQuestion
        case .education:
            return .bookBookmarkFilled
        case .checkForUpdates:
            return .cloudUpload
        case .rateApp:
            return .sparkle
        case .shareApp:
            return .shareUpRight2
        case .twitter:
            return .socialsTwitter
        case .discord:
            return .socialsDiscord
        case .github:
            return .socialsGithub
        case .website:
            return .globe2
        case .privacyPolicy:
            return .shield
        case .termsOfService:
            return .note
        }
    }

    var accessibilityID: String? {
        switch self {
        case .language: return AccessibilityID.Settings.languageCell
        case .currency: return AccessibilityID.Settings.currencyCell
        case .homeDisplay: return AccessibilityID.Settings.homeDisplayCell
        case .widgetWatchlist: return AccessibilityID.Settings.widgetWatchlistCell
        case .vaultSettings: return AccessibilityID.Settings.vaultSettingsCell
        case .faq: return AccessibilityID.Settings.faqCell
        default: return nil
        }
    }

    /// Legal rows end in the larger chevron the design gives them.
    var chevron: SettingsChevron {
        switch self {
        case .privacyPolicy, .termsOfService:
            return .regular
        default:
            return .small
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
        case .rateApp:
            return .link(url: StaticURL.AppStoreVultisigReviewURL)
        case .privacyPolicy:
            return .link(url: StaticURL.PrivacyPolicyURL)
        case .termsOfService:
            return .link(url: StaticURL.TermsOfServiceURL)
        case .education:
            return .link(url: StaticURL.VultisigDocsURL)
        default:
            return .navigation
        }
    }
}
