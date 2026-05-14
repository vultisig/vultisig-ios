//
//  QBTCClaimSnapshotTests.swift
//  VultisigAppTests
//
//  Snapshot coverage for every QBTC claim flow screen so we can detect
//  visual drift against the Figma reference. Each test renders the
//  view in dark mode at iPhone 16 Pro size with deterministic state —
//  no live ViewModels, no animations, no network. The reference PNGs
//  live under __Snapshots__/QBTCClaimSnapshotTests/.
//

import SnapshotTesting
import SwiftUI
import XCTest

@testable import VultisigApp

@MainActor
final class QBTCClaimSnapshotTests: XCTestCase {

    override func setUpWithError() throws {
        // Flip to true to (re)generate reference images, then back to false.
        // isRecording = true

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

    // MARK: - Helpers

    private func snapshot<V: View>(_ view: V, named name: String = #function) {
        assertSnapshot(
            of: view.colorScheme(.dark),
            as: .image(
                precision: 0.99999,
                perceptualPrecision: 0.99999,
                layout: .device(config: .iPhone16Pro)
            ),
            named: name
        )
    }

    private static let fixtureUtxos: [ClaimableUtxo] = [
        ClaimableUtxo(
            txid: "a3f1aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa8d2c",
            vout: 0,
            amount: 75_000_000,
            blockHeight: 1_000_142
        ),
        ClaimableUtxo(
            txid: "b7c4aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1e9f",
            vout: 2,
            amount: 25_000_000,
            blockHeight: 1_000_038
        ),
        ClaimableUtxo(
            txid: "d9e2aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa4a7b",
            vout: 1,
            amount: 10_000_000,
            blockHeight: 1_000_007
        )
    ]

    // MARK: - Quantum Security intro

    func testQuantumSecurityIntroScreen() {
        let view = QuantumSecurityIntroScreen(vault: .example, staticForSnapshot: true)
        snapshot(view)
    }

    func testQuantumSecurityFeatureRow() {
        let view = QuantumSecurityFeatureRow(
            systemImage: "key.fill",
            title: "Generate your quantum key pair",
            subtitle: "Vultisig runs a local MPC ceremony across your vault devices to produce a new key pair."
        )
        .padding(16)
        .background(Theme.colors.bgPrimary)
        snapshot(view)
    }

    // MARK: - BTC promo banner

    func testClaimQbtcPromoBanner() {
        let view = ClaimQbtcPromoBanner(onClaim: {})
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.colors.bgPrimary)
        snapshot(view)
    }

    // MARK: - Selection view (matches Figma 74880:112667 and 75164:107632)

    func testQBTCClaimSelection_allSelected() {
        let viewModel = QBTCClaimViewModel(vault: .example)
        viewModel.snapshotSeed(
            utxos: Self.fixtureUtxos,
            selected: Set(Self.fixtureUtxos.map(\.id))
        )

        let view = QBTCClaimSelectionView(viewModel: viewModel, errorMessage: nil)
            .padding(.horizontal, 16)
            .background(Theme.colors.bgPrimary)
        snapshot(view)
    }

    func testQBTCClaimSelection_partial2of3() {
        let viewModel = QBTCClaimViewModel(vault: .example)
        viewModel.snapshotSeed(
            utxos: Self.fixtureUtxos,
            selected: Set(Self.fixtureUtxos.prefix(2).map(\.id))
        )

        let view = QBTCClaimSelectionView(viewModel: viewModel, errorMessage: nil)
            .padding(.horizontal, 16)
            .background(Theme.colors.bgPrimary)
        snapshot(view)
    }

    func testQBTCClaimSelection_emptySelection() {
        let viewModel = QBTCClaimViewModel(vault: .example)
        viewModel.snapshotSeed(utxos: Self.fixtureUtxos, selected: [])

        let view = QBTCClaimSelectionView(viewModel: viewModel, errorMessage: nil)
            .padding(.horizontal, 16)
            .background(Theme.colors.bgPrimary)
        snapshot(view)
    }

    // MARK: - Blocked / Result
    //
    // Loading no longer has a dedicated screen — the gate-check phase is
    // rendered via the shared `withLoading` modifier on top of the
    // selection skeleton. See `QBTCClaimScreen` + `QBTCClaimViewModel`.

    func testQBTCClaimBlocked_killSwitch() {
        let view = QBTCClaimBlockedView(reason: .killSwitchClosed)
            .background(Theme.colors.bgPrimary)
        snapshot(view)
    }

    func testQBTCClaimBlocked_noUtxos() {
        let view = QBTCClaimBlockedView(reason: .noUtxos)
            .background(Theme.colors.bgPrimary)
        snapshot(view)
    }

    func testQBTCClaimBlocked_unsupportedAddress() {
        let view = QBTCClaimBlockedView(
            reason: .unsupportedBtcAddress(detail: "Taproot (P2TR) addresses are not yet supported.")
        )
        .background(Theme.colors.bgPrimary)
        snapshot(view)
    }

    // MARK: - Running (keysign animation)

    /// The keysign Rive animation can't be deterministically rendered in a
    /// snapshot. We capture the layout including the still-frame container
    /// — actual animation pixels drift, so use a generous precision.
    func testQBTCClaimRunning_signingBTC() {
        let view = QBTCClaimRunningView(phase: .signingBTC, coinLogo: nil)
            .background(Theme.colors.bgPrimary)

        assertSnapshot(
            of: view.colorScheme(.dark),
            as: .image(
                precision: 0.95,
                perceptualPrecision: 0.95,
                layout: .device(config: .iPhone16Pro)
            )
        )
    }

    func testQBTCClaimRunning_generatingProof() {
        let view = QBTCClaimRunningView(phase: .generatingProofAndBroadcasting, coinLogo: nil)
            .background(Theme.colors.bgPrimary)

        assertSnapshot(
            of: view.colorScheme(.dark),
            as: .image(
                precision: 0.95,
                perceptualPrecision: 0.95,
                layout: .device(config: .iPhone16Pro)
            )
        )
    }

    // MARK: - Banner / Claim-button visibility (gated by eligibility checker)

    /// Renders just the BTC-chain `ClaimQbtcPromoBanner` slot with the
    /// eligibility checker in `.eligible` state so the banner is shown.
    /// Mirrors what the BTC chain detail surfaces when there are
    /// claimable UTXOs.
    func testQbtcBanner_visibleWhenEligible() {
        let checker = QBTCClaimEligibilityChecker()
        checker.snapshotSeed(state: .eligible(count: 3, totalSats: 110_000_000))
        snapshot(QbtcVisibilityPreview(checker: checker, showsForBitcoin: true))
    }

    /// `.ineligible` — banner must be hidden. Captures the empty layout
    /// (so a regression that brings the banner back will fail).
    func testQbtcBanner_hiddenWhenIneligible() {
        let checker = QBTCClaimEligibilityChecker()
        checker.snapshotSeed(state: .ineligible)
        snapshot(QbtcVisibilityPreview(checker: checker, showsForBitcoin: true))
    }

    /// QBTC chain-detail Claim button shown when there's at least one
    /// claimable UTXO. Verifies the bottom CTA + reserved 96pt padding.
    func testQbtcClaimButton_visibleWhenEligible() {
        let checker = QBTCClaimEligibilityChecker()
        checker.snapshotSeed(state: .eligible(count: 2, totalSats: 50_000_000))
        snapshot(QbtcVisibilityPreview(checker: checker, showsForBitcoin: false))
    }

    /// `.ineligible` on QBTC chain detail — Claim button absent and the
    /// 96pt reserved bottom padding collapses to 0.
    func testQbtcClaimButton_hiddenWhenIneligible() {
        let checker = QBTCClaimEligibilityChecker()
        checker.snapshotSeed(state: .ineligible)
        snapshot(QbtcVisibilityPreview(checker: checker, showsForBitcoin: false))
    }
}

// MARK: - Snapshot stand-in for the chain-detail visibility predicates

/// Minimal view that mirrors `ChainDetailScreen`'s visibility gates so
/// we can lock the banner-vs-claim-button layout under tests without
/// instantiating the full `ChainDetailScreen` (SwiftData @Model vault +
/// router + EnvironmentObjects). Renders the banner OR the bottom CTA
/// only when `checker.hasClaimableUtxos`, exactly like the production
/// predicates.
private struct QbtcVisibilityPreview: View {
    @ObservedObject var checker: QBTCClaimEligibilityChecker
    let showsForBitcoin: Bool

    private var showsBanner: Bool { showsForBitcoin && checker.hasClaimableUtxos }
    private var showsClaimButton: Bool { !showsForBitcoin && checker.hasClaimableUtxos }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.colors.bgPrimary.ignoresSafeArea()

            VStack(spacing: 20) {
                placeholderHeader

                if showsBanner {
                    ClaimQbtcPromoBanner(onClaim: {})
                }

                Spacer()
            }
            .padding(.bottom, showsClaimButton ? 96 : 0)
            .padding(.horizontal, 16)
        }
        .overlay(alignment: .bottom) {
            if showsClaimButton {
                PrimaryButton(title: "claim".localized) {}
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
    }

    private var placeholderHeader: some View {
        VStack(spacing: 4) {
            Text(showsForBitcoin ? "Bitcoin" : "QBTC")
                .font(Theme.fonts.footnote)
                .foregroundStyle(Theme.colors.textPrimary)
            Text("$31,010.77")
                .font(Theme.fonts.priceLargeTitle)
                .foregroundStyle(Theme.colors.textPrimary)
        }
        .padding(.top, 24)
    }
}
