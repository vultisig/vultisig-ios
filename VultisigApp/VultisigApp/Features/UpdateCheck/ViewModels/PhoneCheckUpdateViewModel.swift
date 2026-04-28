//
//  PhoneCheckUpdateViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

import SwiftUI
import OSLog

@MainActor
class PhoneCheckUpdateViewModel: ObservableObject {
    @Published var showError: Bool = false
    @Published var showDetails: Bool = false
    @Published var showUpdateAlert: Bool = false
    @Published var isUpdateAvailable: Bool = false

    @Published var latestVersionString: String = ""
    @Published var currentVersionString: String = ""

    private let logger = Logger(subsystem: "com.vultisig.app", category: "update-check")
    private let logic = PhoneCheckUpdateLogic()

    func checkForUpdates(isAutoCheck: Bool = false) {
        Task { [weak self] in
            guard let self else { return }

            let currentVersion = logic.currentAppVersion()
            let bundleID = Bundle.main.bundleIdentifier ?? ""

            do {
                let latestVersion = try await logic.fetchLatestAppStoreVersion(bundleID: bundleID)

                // Compare marketing versions only — CFBundleVersion is an
                // internal build counter and mixing it in (e.g. "1.2.300" vs
                // "1.2.1") flips the ordering and suppresses real updates.
                switch logic.compareVersions(currentVersion, latestVersion) {
                case .orderedAscending:
                    self.isUpdateAvailable = true
                    if isAutoCheck {
                        self.showUpdateAlert = true
                    } else {
                        self.showDetails = true
                    }
                case .orderedSame, .orderedDescending:
                    self.isUpdateAvailable = false
                    self.showDetails = true
                }

                self.updateTextValues(currentVersion, latestVersion)
            } catch {
                logger.error("Could not fetch the latest version from the App Store: \(error.localizedDescription)")
                self.showError = true
            }
        }
    }

    func updateTextValues(_ currentVersion: String, _ latestVersion: String) {
        currentVersionString = "Version " + currentVersion
        latestVersionString = "Version " + latestVersion
    }
}

// MARK: - PhoneCheckUpdateLogic

struct PhoneCheckUpdateLogic {

    enum LookupError: Error {
        case missingVersion
    }

    private let httpClient: HTTPClientProtocol

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    func currentAppVersion() -> String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return version
        }
        return "Unknown"
    }

    func fetchLatestAppStoreVersion(bundleID: String) async throws -> String {
        let response = try await httpClient.request(
            AppStoreLookupAPI.lookup(bundleId: bundleID),
            responseType: AppStoreLookupResponse.self
        )

        guard let first = response.data.results.first, let version = first.version else {
            throw LookupError.missingVersion
        }

        return version
    }

    func compareVersions(_ version1: String, _ version2: String) -> ComparisonResult {
        let versionArray1 = version1.split(separator: ".")
        let versionArray2 = version2.split(separator: ".")

        for (v1, v2) in zip(versionArray1, versionArray2) {
            if let v1Int = Int(v1), let v2Int = Int(v2) {
                if v1Int > v2Int {
                    return .orderedDescending
                } else if v1Int < v2Int {
                    return .orderedAscending
                }
            }
        }

        if versionArray1.count > versionArray2.count {
            return .orderedDescending
        } else if versionArray1.count < versionArray2.count {
            return .orderedAscending
        }

        return .orderedSame
    }
}
