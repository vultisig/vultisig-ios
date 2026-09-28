//
//  JoinKeysignFailedStateGuardTests.swift
//  VultisigAppTests
//
//  Pins that a co-signer whose keysign messages failed to prepare stays on the
//  failure screen. `prepareKeysignMessages` rejects an unsupported payload —
//  e.g. a multi-transaction Solana `signAllTransactions` batch (N>1) — by
//  setting `.FailedToStart`, but the deeplink handler then runs
//  `manageQrCodeStates()`. Without the guard that method unconditionally moves
//  a relay payload to `.JoinKeysign`, clobbering the failure and letting the
//  co-signer tap "Join" into the ceremony with no messages to sign. This test
//  fails before the ceremony can be entered.
//

@testable import VultisigApp
import BigInt
import Foundation
import XCTest

@MainActor
final class JoinKeysignFailedStateGuardTests: XCTestCase {

    func testManageQrCodeStatesKeepsFailedToStart() {
        let viewModel = JoinKeysignViewModel()
        // The relay path is the one that would otherwise transition to
        // `.JoinKeysign`; prove the failure survives it.
        viewModel.useVultisigRelay = true
        viewModel.status = .FailedToStart

        viewModel.manageQrCodeStates()

        XCTAssertEqual(
            viewModel.status,
            .FailedToStart,
            "A payload that failed to prepare must not be advanced into the join/ceremony flow"
        )
    }

    func testManageQrCodeStatesStillAdvancesHealthyRelayPayload() {
        let viewModel = JoinKeysignViewModel()
        viewModel.useVultisigRelay = true
        // Default status (.DiscoverSigningMsg) with no blocking payload: the
        // regression guard must not interfere with the normal relay transition.
        viewModel.manageQrCodeStates()

        XCTAssertEqual(viewModel.status, .JoinKeysign)
    }

    // MARK: - Vault-mismatch Cardano body check
    //
    // `prepareKeysignMessages` used to resolve the signing vault as
    // `fetchVaults().first(where: ...) ?? vault` — falling back to the
    // currently selected vault even when it doesn't own the payload. For a
    // SwapKit Cardano prebuilt swap, the body check then runs against that
    // unrelated vault's key, throws, and `.FailedToStart` shadows the
    // `.VaultMismatch` that `manageQrCodeStates()` would otherwise report.

    func testCardanoBodyCheckFailureOnAnUnownedPayloadReportsVaultMismatch() async throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        let viewModel = JoinKeysignViewModel()
        viewModel.vault = Self.makeUnrelatedVault()
        let payload = Self.makeCardanoPrebuiltPayload(vaultPubKeyECDSA: "payload-owner-ecdsa")

        await viewModel.prepareKeysignMessages(keysignPayload: payload)
        viewModel.manageQrCodeStates()

        XCTAssertEqual(
            viewModel.status,
            .VaultMismatch,
            "no local vault owns this payload; the user must be told to switch vaults, not shown a generic failure"
        )
    }

    private static func makeUnrelatedVault() -> Vault {
        let vault = Vault(name: "Unrelated Vault")
        vault.pubKeyECDSA = "unrelated-vault-ecdsa"
        // Valid 32-byte hex so the body check reaches address derivation
        // instead of rejecting the key itself.
        vault.pubKeyEdDSA = String(repeating: "7", count: 64)
        return vault
    }

    /// Real SwapKit `/v3/swap` CBOR (Cardano source, NEAR-routed) — same
    /// fixture `SwapKitCardanoSignerTests` uses. Its two outputs don't belong
    /// to any test-controlled vault, so checking it against an unrelated key
    /// trips `SwapKitCardanoSignerError.tooManyExternalOutputs`.
    private static let cardanoPrebuiltCborHex =
        "84a40081825820f18b3c232d78ca5b1c9e5112314261d839d52a12a5c446c4f80317dc8ac60d48" +
        "000182a200581d618749053dab2309d9b9eba75e17b0406d78302503b4187ca3af260960011a02" +
        "b54eb8a200581d6148838772eed76ee662d3d444e4f8791544e62fa800eb775ec84de62e011a02" +
        "2046f7021a0002888d031a0b324cbba0f5f6"

    private static func makeCardanoPrebuiltPayload(vaultPubKeyECDSA: String) -> KeysignPayload {
        let adaCoin = Coin(
            asset: CoinMeta.make(chain: .cardano, ticker: "ADA", decimals: 6, isNativeToken: true),
            address: "addr1v9yg8pmjamtkaenz602yfe8c0y25fe304qqwka67epx7vtszj8749",
            hexPublicKey: ""
        )
        let usdcCoin = Coin(
            asset: CoinMeta.make(chain: .ethereum, ticker: "USDC", decimals: 6, isNativeToken: false),
            address: "0xtest",
            hexPublicKey: ""
        )
        let swapPayload = SwapKitSwapPayload(
            fromCoin: adaCoin,
            toCoin: usdcCoin,
            fromAmount: BigInt(45_500_000),
            toAmountDecimal: 0,
            txType: "CARDANO_PREBUILT",
            txPayload: Data(hexString: cardanoPrebuiltCborHex)!,
            targetAddress: "addr1vy9sgnlkxkwg58axypgwllhgt522k045f0q7zst5faxqc2sgggj3a",
            inboundAddress: "addr1vy9sgnlkxkwg58axypgwllhgt522k045f0q7zst5faxqc2sgggj3a",
            memo: nil,
            subProvider: "NEAR",
            swapID: "test"
        )
        return KeysignPayload(
            coin: adaCoin,
            toAddress: swapPayload.targetAddress,
            toAmount: BigInt(45_500_000),
            chainSpecific: .Cardano(byteFee: 44, sendMaxAmount: false, ttl: 190_000_000),
            utxos: [],
            memo: nil,
            swapPayload: .swapkit(swapPayload),
            approvePayload: nil,
            vaultPubKeyECDSA: vaultPubKeyECDSA,
            vaultLocalPartyID: "payload-owner-party",
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
