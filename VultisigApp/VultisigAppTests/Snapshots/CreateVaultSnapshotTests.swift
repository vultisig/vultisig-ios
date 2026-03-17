//
//  CreateVaultSnapshotTests.swift
//  VultisigAppTests
//

import SnapshotTesting
import SwiftUI
import XCTest

@testable import VultisigApp

@MainActor
final class CreateVaultSnapshotTests: XCTestCase {

    override func setUpWithError() throws {
        // Set to true to generate/update reference images, then back to false
        // isRecording = true

        // Reset @AppStorage keys so snapshots are deterministic
        let defaults = UserDefaults.standard
        [
            "showOnboarding",
            "showCover",
            "isAuthenticationEnabled",
            "didAskForAuthentication",
            "lastRecordedTime",
            "vaultName",
            "selectedPubKeyECDSA"
        ].forEach { defaults.removeObject(forKey: $0) }
    }

    // MARK: - CreateVaultView

    /// Snapshot after animations settle (buttons appear after 0.3s delays)
    func testCreateVaultScreen_iPhone16Pro() {
        let vc = UIHostingController(
            rootView: CreateVaultView()
                .environmentObject(AppViewModel())
                .environmentObject(DeeplinkViewModel())
                .colorScheme(.dark)
        )
        vc.view.frame = UIScreen.main.bounds

        // Add to key window so onAppear/onLoad triggers fire
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? UIWindow()
        window.rootViewController = vc
        window.makeKeyAndVisible()

        // Let the run loop process the async dispatches (0.1s + 0.2s + 0.3s delays)
        let expectation = expectation(description: "Wait for animations")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)

        assertSnapshot(
            of: vc,
            as: .image(on: .iPhone16Pro, precision: 0.98, perceptualPrecision: 0.95)
        )
    }

    // MARK: - WelcomeView (renders synchronously — no wait needed)

    func testWelcomeView_loading() {
        let viewModel = AppViewModel()
        viewModel.didUserCancelAuthentication = false

        let view = WelcomeView()
            .environmentObject(viewModel)
            .colorScheme(.dark)

        assertSnapshot(
            of: view,
            as: .image(layout: .device(config: .iPhone16Pro))
        )
    }

    func testWelcomeView_tryAgainState() {
        let viewModel = AppViewModel()
        viewModel.didUserCancelAuthentication = true

        let view = WelcomeView()
            .environmentObject(viewModel)
            .colorScheme(.dark)

        assertSnapshot(
            of: view,
            as: .image(layout: .device(config: .iPhone16Pro))
        )
    }
}
