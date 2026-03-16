//
//  HomeScreenTests.swift
//  VultisigAppUITests
//

import XCTest

final class HomeScreenTests: VultisigUITestCase {

    // MARK: - Launch Tests

    func testAppLaunchesSuccessfully() throws {
        launchApp()

        // App should land on either home (with vaults) or create vault (fresh install)
        let homeVisible = app.buttons[AccessibilityID.Home.vaultSelector]
            .waitForExistence(timeout: 10)
        let createVaultVisible = app.buttons[AccessibilityID.Onboarding.createVaultButton]
            .waitForExistence(timeout: 2)

        XCTAssertTrue(
            homeVisible || createVaultVisible,
            "App should show either home screen or create vault screen"
        )
        takeScreenshot(name: "App Launch")
    }

    // MARK: - Create Vault Screen (Fresh Install)

    func testCreateVaultScreenShowsButtons() throws {
        launchApp()

        // If there are no vaults, we should see the create vault screen
        guard isOnCreateVaultScreen else {
            // If vaults exist, this test is not applicable — skip gracefully
            return
        }

        createVaultPage.assertVisible()
        XCTAssertTrue(createVaultPage.getStartedButton.exists, "Get Started button should be visible")
        XCTAssertTrue(createVaultPage.importButton.exists, "Import button should be visible")
        takeScreenshot(name: "Create Vault Screen")
    }

    // MARK: - Home Screen (With Vaults)

    func testHomeScreenShowsVaultSelector() throws {
        launchApp()

        guard isOnHomeScreen else {
            // No vaults — home screen not reachable without vault creation
            return
        }

        homePage.assertVisible()
        XCTAssertTrue(homePage.vaultSelector.exists, "Vault selector should be visible")
    }

    func testHomeScreenShowsWalletTab() throws {
        launchApp()

        guard isOnHomeScreen else { return }

        homePage.assertVisible()
        homePage.assertTabsExist()
    }

    func testNavigateToSettings() throws {
        launchApp()

        guard isOnHomeScreen else { return }

        homePage.assertVisible()
        let settings = homePage.tapSettings()
        settings.assertVisible()
        takeScreenshot(name: "Settings Screen")
    }

    func testTapVaultSelector() throws {
        launchApp()

        guard isOnHomeScreen else { return }

        homePage.assertVisible()
        homePage.tapVaultSelector()
        takeScreenshot(name: "Vault Selector")
    }
}
