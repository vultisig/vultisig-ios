//
//  SendPreviewOverrideTests.swift
//  VultisigAppTests
//
//  Covers `SendPreviewOverride.makeIfNeeded` — the opt-in pairing/QR-preview
//  override. A Circle USDC withdraw signs a native-ETH MSCA `execute(...)` call
//  (the keysign payload reads "0 ETH → MSCA"), while the user is moving
//  "N USDC → vault". The override surfaces the display values in the pairing
//  hero WITHOUT touching the signed payload. For a regular send the display tx
//  coin and the signed payload coin match, so the override is `nil` and the
//  preview keeps reading from the payload.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class SendPreviewOverrideTests: XCTestCase {

    func testOverrideSurfacesDisplayUsdcWhenSignedCoinDiffers() throws {
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false)
        let vaultRecipient = "0x1111111111111111111111111111111111111111"
        let displayTx = try makeTransaction(coin: usdc, toAddress: vaultRecipient, amount: "5")

        // Signed payload is the native-ETH MSCA execute() call — "0 ETH → MSCA".
        let signed = makePayload(
            coin: makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true),
            toAddress: "0x2222222222222222222222222222222222222222",
            toAmount: BigInt(0)
        )

        let override = SendPreviewOverride.makeIfNeeded(displayTx: displayTx, signedPayload: signed)

        let unwrapped = try XCTUnwrap(override, "differing coins must produce a display override")
        XCTAssertEqual(unwrapped.amount, "5 USDC", "preview must show the USDC amount, not 0 ETH")
        XCTAssertEqual(unwrapped.toAddress, vaultRecipient, "preview must show the vault recipient, not the MSCA")
        XCTAssertEqual(unwrapped.coinLogo, usdc.logo)
    }

    func testOverrideIsNilForRegularSendWhereCoinsMatch() throws {
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false)
        let displayTx = try makeTransaction(coin: usdc, toAddress: "0x1111111111111111111111111111111111111111", amount: "5")

        // A normal ERC-20 send signs the very same coin it displays.
        let signed = makePayload(coin: usdc, toAddress: displayTx.toAddress, toAmount: BigInt(5_000_000))

        XCTAssertNil(
            SendPreviewOverride.makeIfNeeded(displayTx: displayTx, signedPayload: signed),
            "matching coins must keep the payload-derived preview untouched"
        )
    }

    // MARK: - Helpers

    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int, isNative: Bool) -> Coin {
        let asset = CoinMeta.make(chain: chain, ticker: ticker, decimals: decimals, isNativeToken: isNative)
        return Coin(asset: asset, address: "test-address-\(ticker)", hexPublicKey: "")
    }

    private func makeTransaction(coin: Coin, toAddress: String, amount: String) throws -> SendTransaction {
        let vault = try TestStore.makeVault()
        return SendTransaction(
            coin: coin, vault: vault, fromAddress: coin.address,
            toAddress: toAddress, toAddressLabel: nil,
            amount: amount, amountInFiat: "", memo: "",
            gas: .zero, fee: .zero, feeMode: .default,
            estimatedGasLimit: nil, customGasLimit: nil, customByteFee: nil,
            sendMaxAmount: false, isStakingOperation: false,
            transactionType: .unspecified,
            memoFunctionDictionary: [:], wasmContractPayload: nil,
            feeCoin: coin
        )
    }

    private func makePayload(coin: Coin, toAddress: String, toAmount: BigInt) -> KeysignPayload {
        KeysignPayload(
            coin: coin,
            toAddress: toAddress,
            toAmount: toAmount,
            chainSpecific: .Ethereum(maxFeePerGasWei: BigInt(1), priorityFeeWei: BigInt(1), nonce: 0, gasLimit: BigInt(21_000)),
            utxos: [],
            memo: "0xb61d27f6",
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "pub",
            vaultLocalPartyID: "party",
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: false,
            signData: nil
        )
    }
}
