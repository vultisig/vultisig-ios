//
//  SwapDoneSummaryCardDAppMetadataTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import BigInt
import XCTest

/// A dApp swap reaches the co-signer as a swap payload, so it renders through
/// the swap card rather than the default done slot that draws the banner.
@MainActor
final class SwapDoneSummaryCardDAppMetadataTests: XCTestCase {

    private let dapp = DAppMetadata(name: "Swap Raydium", url: "https://raydium.io", iconURL: "https://raydium.io/favicon.ico")

    private var token: TestContextToken!

    override func setUpWithError() throws {
        token = try TestStore.installInMemoryContainer()
    }

    override func tearDown() {
        TestStore.restore(token)
        token = nil
    }

    func testCosignerCardCarriesTheRequestingDApp() {
        let card = makeCosignerCard(dappMetadata: dapp)

        XCTAssertEqual(card.fields.dappMetadata, dapp)
    }

    func testCosignerCardHasNoDAppForAnInAppSwap() {
        let card = makeCosignerCard(dappMetadata: nil)

        XCTAssertNil(card.fields.dappMetadata)
    }

    private func makeCosignerCard(dappMetadata: DAppMetadata?) -> SwapDoneSummaryCard {
        SwapDoneSummaryCard.cosigner(
            keysignPayload: makeKeysignPayload(dappMetadata: dappMetadata),
            vault: TestStore.makeVault(pubKey: "swap-done-dapp"),
            summaryViewModel: JoinKeysignSummaryViewModel(),
            txHash: "hash",
            networkFee: "0.000005 SOL"
        )
    }

    private func makeKeysignPayload(dappMetadata: DAppMetadata?) -> KeysignPayload {
        let asset = CoinMeta(
            chain: .ethereum,
            ticker: "ETH",
            logo: "logo",
            decimals: 18,
            priceProviderId: "eth",
            contractAddress: "",
            isNativeToken: true
        )
        return KeysignPayload(
            coin: Coin(asset: asset, address: "0xsender", hexPublicKey: ""),
            toAddress: "0xrecipient",
            toAmount: BigInt(1),
            chainSpecific: .Ethereum(maxFeePerGasWei: 0, priorityFeeWei: 0, nonce: 0, gasLimit: 21000),
            utxos: [],
            memo: nil,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "",
            vaultLocalPartyID: "",
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: false,
            signData: nil,
            dappMetadata: dappMetadata
        )
    }
}
