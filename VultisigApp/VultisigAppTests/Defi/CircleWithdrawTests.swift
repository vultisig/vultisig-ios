//
//  CircleWithdrawTests.swift
//  VultisigAppTests
//
//  Covers the Circle USDC-yield withdraw signing path. The regression guard is
//  `makeWithdrawalKeysignPayload`: a withdraw is a contract call to the MSCA —
//  `execute(USDC, 0, transfer(vault, amount))` carried in `memo` — and the EVM
//  signer only forwards `memo` as `tx.data` on the NATIVE-coin path. If the
//  payload coin is the USDC ERC-20 token, the signer instead builds
//  `transfer(MSCA, 0)` and drops the memo — a no-op that confirms but moves 0
//  USDC. `getWithdrawalValues` is the pure ABI encoder for that calldata.
//

import BigInt
import WalletCore
import XCTest
@testable import VultisigApp

@MainActor
final class CircleWithdrawTests: XCTestCase {

    private let usdcContract = CircleConstants.usdcMainnet
    private let mscaAddress = "0x2222222222222222222222222222222222222222"
    private let recipient = "0x1111111111111111111111111111111111111111"

    // execute(address,uint256,bytes)
    private let executeSelector = "b61d27f6"
    // ERC-20 transfer(address,uint256)
    private let transferSelector = "a9059cbb"

    // MARK: - getWithdrawalValues — ERC-20 (USDC) path

    func testWithdrawalValuesEncodesExecuteWrappingTransferForUsdc() throws {
        let vault = makeVault(mscaAddress: mscaAddress)
        let amount = BigInt(1_000_000) // 1 USDC (6 decimals) = 0xF4240

        let (to, value, data) = try CircleService.shared.getWithdrawalValues(
            vault: vault,
            recipientAddress: recipient,
            amount: amount,
            info: .init(usdcContract: usdcContract),
            isNative: false
        )

        // Call targets the MSCA and sends 0 ETH value — the USDC moves via the inner transfer.
        XCTAssertEqual(to, mscaAddress)
        XCTAssertEqual(value, BigInt(0))

        let hex = data.hexString.lowercased()
        XCTAssertTrue(hex.hasPrefix(executeSelector), "outer call must be execute(address,uint256,bytes)")
        XCTAssertTrue(hex.contains(transferSelector), "inner calldata must be ERC-20 transfer(address,uint256)")
        XCTAssertTrue(hex.contains(noPrefix(usdcContract)), "execute target should be the USDC contract")
        XCTAssertTrue(hex.contains(noPrefix(recipient)), "inner transfer recipient should be the vault address")
        XCTAssertTrue(hex.contains("f4240"), "inner transfer amount (1_000_000 = 0xF4240) should be encoded")
    }

    // MARK: - getWithdrawalValues — native ETH path

    func testWithdrawalValuesEncodesPlainExecuteForNative() throws {
        let vault = makeVault(mscaAddress: mscaAddress)
        let amount = BigInt(1_000_000)

        let (to, value, data) = try CircleService.shared.getWithdrawalValues(
            vault: vault,
            recipientAddress: recipient,
            amount: amount,
            info: .init(usdcContract: usdcContract),
            isNative: true
        )

        XCTAssertEqual(to, mscaAddress)
        XCTAssertEqual(value, amount, "native withdraw forwards the ETH value to the execute call")

        let hex = data.hexString.lowercased()
        XCTAssertTrue(hex.hasPrefix(executeSelector))
        XCTAssertFalse(hex.contains(transferSelector), "native withdraw has empty inner data — no ERC-20 transfer")
        XCTAssertTrue(hex.contains(noPrefix(recipient)), "execute target is the recipient for a native withdraw")
    }

    func testWithdrawalValuesThrowsForInvalidRecipient() {
        let vault = makeVault(mscaAddress: mscaAddress)
        XCTAssertThrowsError(try CircleService.shared.getWithdrawalValues(
            vault: vault,
            recipientAddress: "not-an-address",
            amount: BigInt(1),
            info: .init(usdcContract: usdcContract),
            isNative: false
        ))
    }

    func testWithdrawalValuesThrowsWhenWalletAddressMissing() {
        let vault = makeVault(mscaAddress: nil)
        XCTAssertThrowsError(try CircleService.shared.getWithdrawalValues(
            vault: vault,
            recipientAddress: recipient,
            amount: BigInt(1),
            info: .init(usdcContract: usdcContract),
            isNative: false
        ))
    }

    // MARK: - makeWithdrawalKeysignPayload — the #4484 regression guard

    func testWithdrawalPayloadUsesNativeCoinNotUsdc() throws {
        let vault = makeVault(mscaAddress: mscaAddress)
        vault.coins = [
            makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true),
            makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false)
        ]
        let memo = "0xb61d27f6deadbeef"

        let payload = try CircleViewLogic().makeWithdrawalKeysignPayload(
            vault: vault,
            chain: .ethereum,
            to: mscaAddress,
            value: BigInt(0),
            memoHex: memo,
            chainSpecific: ethChainSpecific()
        )

        // Crux of #4484: an ERC-20 coin makes the EVM signer drop the memo and sign
        // transfer(MSCA, 0) — a no-op. The payload must carry the NATIVE coin so the
        // signer routes the execute() calldata through `memo → tx.data`.
        XCTAssertTrue(payload.coin.isNativeToken, "withdraw payload must use the native coin")
        XCTAssertEqual(payload.coin.ticker, "ETH")
        XCTAssertNotEqual(payload.coin.ticker, "USDC")

        // The execute() calldata must survive verbatim, targeting the MSCA with 0 value.
        XCTAssertEqual(payload.toAddress, mscaAddress)
        XCTAssertEqual(payload.toAmount, BigInt(0))
        XCTAssertEqual(payload.memo, memo)
    }

    func testWithdrawalPayloadThrowsWhenNoNativeCoin() {
        let vault = makeVault(mscaAddress: mscaAddress)
        vault.coins = [makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false)]

        XCTAssertThrowsError(try CircleViewLogic().makeWithdrawalKeysignPayload(
            vault: vault,
            chain: .ethereum,
            to: mscaAddress,
            value: BigInt(0),
            memoHex: "0x",
            chainSpecific: ethChainSpecific()
        ))
    }

    // MARK: - Helpers

    private func noPrefix(_ address: String) -> String {
        String(address.dropFirst(2)).lowercased()
    }

    private func makeVault(mscaAddress: String?) -> Vault {
        let vault = Vault(
            name: "Test Vault",
            signers: [],
            pubKeyECDSA: "test-pub-ecdsa",
            pubKeyEdDSA: "test-pub-eddsa",
            keyshares: [],
            localPartyID: "party",
            hexChainCode: "hex",
            resharePrefix: nil,
            libType: .DKLS
        )
        vault.circleWalletAddress = mscaAddress
        return vault
    }

    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int, isNative: Bool) -> Coin {
        let asset = CoinMeta.make(chain: chain, ticker: ticker, decimals: decimals, isNativeToken: isNative)
        return Coin(asset: asset, address: "test-address-\(ticker)", hexPublicKey: "")
    }

    private func ethChainSpecific() -> BlockChainSpecific {
        .Ethereum(maxFeePerGasWei: BigInt(1), priorityFeeWei: BigInt(1), nonce: 0, gasLimit: BigInt(21_000))
    }
}
