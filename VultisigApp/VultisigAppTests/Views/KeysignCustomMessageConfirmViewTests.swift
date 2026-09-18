//
//  KeysignCustomMessageConfirmViewTests.swift
//  VultisigAppTests
//
//  The custom-message verify screen only draws its hero section — and the
//  separator under it — when there is something to put there. A decoded
//  function name exists for EVM calldata alone, so for every other chain the
//  dApp banner has to be enough on its own to open the section.
//

@testable import VultisigApp
import XCTest

@MainActor
final class KeysignCustomMessageConfirmViewTests: XCTestCase {

    private let polymarket = DAppMetadata(name: "Polymarket", url: "https://polymarket.com", iconURL: "")

    /// `JoinKeysignViewModel` builds a `Vault` on init, which must not land in
    /// the app's real store.
    private var token: TestContextToken!

    override func setUpWithError() throws {
        token = try TestStore.installInMemoryContainer()
    }

    override func tearDown() {
        TestStore.restore(token)
        token = nil
    }

    func testHeroSectionHiddenWithoutMetadataOrFunctionName() {
        let viewModel = makeViewModel(dappMetadata: nil)

        XCTAssertFalse(KeysignCustomMessageConfirmView(viewModel: viewModel).hasHeroSection)
    }

    func testHeroSectionShownForMetadataAlone() {
        let viewModel = makeViewModel(chain: "Cosmos", dappMetadata: polymarket)

        XCTAssertNil(viewModel.decodedFunctionName)
        XCTAssertTrue(KeysignCustomMessageConfirmView(viewModel: viewModel).hasHeroSection)
    }

    func testHeroSectionShownForFunctionNameAlone() {
        let viewModel = makeViewModel(dappMetadata: nil)
        viewModel.decodedFunctionName = "approve"

        XCTAssertTrue(KeysignCustomMessageConfirmView(viewModel: viewModel).hasHeroSection)
    }

    func testEmptyMetadataDoesNotOpenTheHeroSection() {
        let viewModel = makeViewModel(dappMetadata: DAppMetadata(name: "", url: "", iconURL: ""))

        XCTAssertFalse(KeysignCustomMessageConfirmView(viewModel: viewModel).hasHeroSection)
    }

    private func makeViewModel(chain: String = "Ethereum", dappMetadata: DAppMetadata?) -> JoinKeysignViewModel {
        let viewModel = JoinKeysignViewModel()
        viewModel.customMessagePayload = CustomMessagePayload(
            method: "personal_sign",
            message: "0x48656c6c6f",
            vaultPublicKeyECDSA: "02abc",
            vaultLocalPartyID: "party",
            chain: chain,
            dappMetadata: dappMetadata
        )
        return viewModel
    }
}
