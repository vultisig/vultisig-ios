//
//  SecurityScannerSettingsService.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 29/07/2025.
//

import SwiftUI

protocol SecurityScannerSettingsServiceProtocol {
    var isEnabled: Bool { get }
    func saveSecurityScannerStatus(enable: Bool)
}

struct SecurityScannerSettingsService: SecurityScannerSettingsServiceProtocol {
    @AppStorage("VultisigSecurityScanEnabled") private var securityScannerEnabled: Bool = true

    var isEnabled: Bool { securityScannerEnabled }

    func saveSecurityScannerStatus(enable: Bool) {
        securityScannerEnabled = enable
    }
}
