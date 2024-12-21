//
//  MacCheckUpdateViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-11.
//

import SwiftUI

class MacCheckUpdateViewModel: ObservableObject {
    @Published var showError: Bool = false
    @Published var showDetails: Bool = false
    @Published var showUpdateAlert: Bool = false
    @Published var isUpdateAvailable: Bool = false
    
    @Published var latestVersion: String = ""
    @Published var latestVersionBase: String = ""
    @Published var currentVersion: String = ""
    
    func resetData() {
        showError = false
        showDetails = false
    }
    
    func checkForUpdates(isAutoCheck: Bool = false) {
        resetData()
        
        fetchGitHubReleases { releases in
            if let releases = releases {
                self.checkCurrentVersion(releases, isAutoCheck: isAutoCheck)
            } else {
                self.showErrorMessage()
                print("Failed to fetch or decode GitHub releases.")
            }
        }
    }
    
    func checkCurrentVersion(_ releases: [UpdateVersion], isAutoCheck: Bool) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        
        guard let latestRelease = releases.first(where: { !$0.prerelease })?.tagName,
              let currentRelease = version,
              let currentBuild = build else {
            showErrorMessage()
            return
        }
        
        let latest = latestRelease.replacingOccurrences(of: "release-", with: "v")
        let current = "v" + currentRelease.replacingOccurrences(of: "release-", with: "v") + "." + currentBuild
        
        showDetailView(latest: latest, current: current, isAutoCheck: isAutoCheck)
    }
    
    func fetchGitHubReleases(completion: @escaping ([UpdateVersion]?) -> Void) {
        let urlString = Endpoint.updateVersionCheck
        guard let url = URL(string: urlString) else {
            print("Invalid URL string.")
            showErrorMessage()
            completion(nil)
            return
        }
        
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Error fetching data: \(error.localizedDescription)")
                self.showErrorMessage()
                completion(nil)
                return
            }
            
            guard let data = data else {
                print("No data received.")
                self.showErrorMessage()
                completion(nil)
                return
            }
            
            do {
                let decoder = JSONDecoder()
                let releases = try decoder.decode([UpdateVersion].self, from: data)
                completion(releases)
            } catch {
                print("Error decoding JSON: \(error.localizedDescription)")
                self.showErrorMessage()
                completion(nil)
            }
        }
        
        task.resume()
    }
    
    func showErrorMessage() {
        DispatchQueue.main.async {
            self.showError = true
        }
    }
    
    func showDetailView(latest: String, current: String, isAutoCheck: Bool) {
        DispatchQueue.main.async {
            self.latestVersionBase = latest
            self.latestVersion = latest.replacingOccurrences(of: "v", with: "Version ")
            self.currentVersion = current.replacingOccurrences(of: "v", with: "Version ")
            
            let comparisonResult = self.compareVersions(current, latest)
            self.isUpdateAvailable = comparisonResult == .orderedAscending
            
            if isAutoCheck {
                if self.isUpdateAvailable {
                    self.showUpdateAlert = true
                }
            } else {
                self.showDetails = true
            }
        }
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
