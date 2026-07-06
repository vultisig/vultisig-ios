//
//  OnboardingOverviewContent.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 06/07/2026.
//

import Foundation

/// Resolves the backup-guide copy shown by `OnboardingOverviewScreen`
/// for each flow that lands on it: key import, vault creation, and
/// reshare. Keys are resolved here (and formatted by the view) so the
/// per-flow selection stays unit-testable.
struct OnboardingOverviewContent {

    enum RowSubtitle: Equatable {
        case plain(key: String)
        case secureCount(key: String, count: Int)
    }

    let tssType: TssType
    let setupType: KeyImportSetupType

    var isKeyImport: Bool {
        tssType == .KeyImport
    }

    var isReshare: Bool {
        tssType == .Reshare
    }

    var descriptionKey: String {
        isKeyImport || isReshare ? "backupsDescription" : "backupsDescriptionVault"
    }

    var descriptionHighlightKey: String? {
        isKeyImport || isReshare ? nil : "backupsDescriptionVaultHighlight"
    }

    var backupRowTitleKey: String {
        if !isKeyImport && setupType == .fast {
            return "backupDeviceDriver"
        }
        return "backupEachDevice"
    }

    var backupRowHighlightKey: String? {
        if !isKeyImport && setupType == .fast {
            return "backupDeviceDriverDescriptionHighlight"
        }
        return nil
    }

    var backupRowSubtitle: RowSubtitle {
        if isKeyImport {
            return .plain(key: "backupEachDeviceDescription")
        }
        switch setupType {
        case .fast:
            return .plain(key: "backupDeviceDriverDescription")
        case .secure(let count):
            // The reshare guide uses the generic repeat-per-device copy
            // from the redesign rather than the total-count variant.
            return isReshare
                ? .plain(key: "backupEachDeviceDescription")
                : .secureCount(key: "backupEachDeviceDescriptionSecure", count: count)
        }
    }

    var storeSeparatelyRowSubtitleKey: String {
        if !isKeyImport, !isReshare, case .secure = setupType {
            return "storeBackupsSeparatelyDescriptionSecure"
        }
        return "storeBackupsSeparatelyDescription"
    }

    /// Reshare invalidates every backup taken before the session, so the
    /// guide surfaces a dedicated row for it.
    var showsOldBackupsRow: Bool {
        isReshare
    }

    var buttonTitleKey: String {
        isKeyImport || isReshare ? "continue" : "iUnderstand"
    }
}
