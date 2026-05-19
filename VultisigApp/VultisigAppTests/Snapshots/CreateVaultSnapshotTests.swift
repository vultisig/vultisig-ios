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

    /// Renders the fully-revealed static layout via `staticForSnapshot: true`,
    /// which (a) seeds the reveal `@State` flags to `true` so the spring
    /// animation never triggers, and (b) swaps the Rive logo for a static
    /// image. The captured frame is a deterministic still — no animations,
    /// no `asyncAfter`, no live key window.
    func testCreateVaultScreen_iPhone16Pro() {
        let view = CreateVaultView(staticForSnapshot: true)
            .environmentObject(AppViewModel())
            .environmentObject(DeeplinkViewModel())
            .colorScheme(.dark)

        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.99999,
                perceptualPrecision: 0.99999,
                layout: .device(config: .iPhone16Pro)
            )
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
            as: .image(
                precision: 0.99999,
                perceptualPrecision: 0.99999,
                layout: .device(config: .iPhone16Pro)
            )
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
            as: .image(
                precision: 0.99999,
                perceptualPrecision: 0.99999,
                layout: .device(config: .iPhone16Pro)
            )
        )
    }
}
