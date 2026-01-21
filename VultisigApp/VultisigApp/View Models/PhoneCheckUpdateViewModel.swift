//
//  PhoneCheckUpdateViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

import SwiftUI

class PhoneCheckUpdateViewModel: ObservableObject {
    @Published var showError: Bool = false
    @Published var showDetails: Bool = false
    @Published var showUpdateAlert: Bool = false
    @Published var isUpdateAvailable: Bool = false

    @Published var latestVersionString: String = ""
    @Published var currentVersionString: String = ""

    private let logic = PhoneCheckUpdateLogic()

    func checkForUpdates(isAutoCheck: Bool = false) {
        let currentVersion = logic.currentAppVersion()
        let bundleID = Bundle.main.bundleIdentifier ?? ""

        logic.fetchLatestAppStoreVersion(bundleID: bundleID) { [weak self] latestVersion in
            guard let self else { return }
            guard let latestVersion = latestVersion else {
                self.showErrorMessage()
                print("Could not fetch the latest version from the App Store.")
                return
            }

            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
            let fullCurrentVersion = currentVersion + "." + build

            let comparisonResult = self.logic.compareVersions(fullCurrentVersion, latestVersion)
            DispatchQueue.main.async {
                switch comparisonResult {
                case .orderedAscending:
                    self.isUpdateAvailable = true

                    if isAutoCheck {
                        self.showUpdateAlert = true
                    } else {
                        self.showDetails = true
                    }
                case .orderedSame:
                    self.isUpdateAvailable = false
                    self.showDetails = true
                case .orderedDescending:
                    self.isUpdateAvailable = false
                    self.showDetails = true
                }

                self.updateTextValues(fullCurrentVersion, latestVersion)
            }
        }
    }

    func updateTextValues(_ currentVersion: String, _ latestVersion: String) {
        currentVersionString = "Version " + currentVersion
        latestVersionString = "Version " + latestVersion
    }

    func showErrorMessage() {
        DispatchQueue.main.async {
            self.showError = true
        }
    }
}

// MARK: - PhoneCheckUpdateLogic

struct PhoneCheckUpdateLogic {

    func currentAppVersion() -> String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return version
        }
        return "Unknown"
    }

    func fetchLatestAppStoreVersion(bundleID: String, completion: @escaping (String?) -> Void) {
        let urlStr = "https://itunes.apple.com/lookup?bundleId=\(bundleID)"
        guard let url = URL(string: urlStr) else {
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, error in
            if let error = error {
                print("Error fetching data from App Store: \(error.localizedDescription)")
                completion(nil)
                return
            }

            guard let data = data else {
                completion(nil)
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any], let results = json["results"] as? [[String: Any]], let appStoreVersion = results.first?["version"] as? String {
                    let buildNumber = results.first?["bundleVersion"] as? String ?? "0"
                    completion(appStoreVersion + "." + buildNumber)
                } else {
                    completion(nil)
                }
            } catch {
                print("Error parsing App Store data: \(error.localizedDescription)")
                completion(nil)
            }
        }.resume()
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
