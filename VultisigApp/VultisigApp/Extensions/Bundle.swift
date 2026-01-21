//
//  Bundle.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 11/08/2025.
//

import Foundation

extension Bundle {
    var appVersionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String
        let build = infoDictionary?["CFBundleVersion"] as? String

        return "Version \(version ?? "1").\(build ?? "1")"
    }
}
