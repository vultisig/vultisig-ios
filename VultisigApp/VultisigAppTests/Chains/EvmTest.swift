//
//  EvmTest.swift
//  VultisigApp
//
//  Created by Johnny Luo on 27/9/2024.
//

@testable import VultisigApp
import WalletCore
import XCTest
import BigInt

final class EVMChainsHelperTest: XCTestCase {
    let hexPublicKey = "023e4b76861289ad4528b33c2fd21b3a5160cd37b3294234914e21efb6ed4a452b"
    let hexChainCode = "c9b189a8232b872b8d9ccd867d0db316dd10f56e729c310fe072adf5fd204ae7"

    func testGetCoin() throws {
        let vaultForTest = Vault(name: "TestVault")
        vaultForTest.pubKeyECDSA = hexPublicKey
        vaultForTest.hexChainCode = hexChainCode
        let eth = try CoinFactory.create(
            asset: TokensStore.Token.ethereum,
            publicKeyECDSA: hexPublicKey,
            publicKeyEdDSA: "",
            hexChainCode: hexChainCode,
            isDerived: false
        )
        XCTAssertEqual(eth.hexPublicKey, "03bb1adf8c0098258e4632af6c055c37135477e269b7e7eb4f600fe66d9ca9fd78")
        XCTAssertEqual(eth.address, "0xe5F238C95142be312852e864B830daADB9B7D290")
    }

    func testGetPreKeysignImage() throws {
        let vaultForTest = Vault(name: "TestVault")
        vaultForTest.pubKeyECDSA = hexPublicKey
        vaultForTest.hexChainCode = hexChainCode
        let eth = try CoinFactory.create(
            asset: TokensStore.Token.ethereum,
            publicKeyECDSA: hexPublicKey,
            publicKeyEdDSA: "",
            hexChainCode: hexChainCode,
            isDerived: false
        )
        let keysignPayload = KeysignPayload(
            coin: eth,
            toAddress: "0xfA0635a1d083D0bF377EFbD48DA46BB17e0106cA",
            toAmount: 10000000,
            chainSpecific: BlockChainSpecific.Ethereum(
                maxFeePerGasWei: BigInt(10),
                priorityFeeWei: BigInt(1),
                nonce: 0,
                gasLimit: BigInt(24000)
            ),
            utxos: [],
            memo: "voltix",
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "ECDSAKey",
            vaultLocalPartyID: "localPartyID",
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
        let evmHelper = EVMHelper(coinType: .ethereum)
        let preImageHashes = try evmHelper.getPreSignedImageHash(keysignPayload: keysignPayload)
        XCTAssertEqual(preImageHashes.count, 1)
        XCTAssertEqual(preImageHashes[0], "1e93ef6b20b01723e95128aed8786d43c7c53a12959a21ef36cf408a6d7115de")
    }

    /// Builds a native-coin EVM memo-call payload at a fixed nonce, optionally
    /// with a non-swap approve bundled. Shared by the increment-nonce and
    /// non-swap-bundle tests below.
    private func makeNativeMemoCallPayload(coin: Coin, nonce: Int64, approve: ERC20ApprovePayload?) -> KeysignPayload {
        KeysignPayload(
            coin: coin,
            toAddress: "0xA73424f1Ac94b3ef0D0c9af4F2967c87D4AF25D9",
            toAmount: 0,
            chainSpecific: BlockChainSpecific.Ethereum(
                maxFeePerGasWei: BigInt(10),
                priorityFeeWei: BigInt(1),
                nonce: nonce,
                gasLimit: BigInt(600000)
            ),
            utxos: [],
            memo: "0x6e553f65",
            swapPayload: nil,
            approvePayload: approve,
            vaultPubKeyECDSA: "ECDSAKey",
            vaultLocalPartyID: "localPartyID",
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

    private func ethCoin() throws -> Coin {
        try CoinFactory.create(
            asset: TokensStore.Token.ethereum,
            publicKeyECDSA: hexPublicKey,
            publicKeyEdDSA: "",
            hexChainCode: hexChainCode,
            isDerived: false
        )
    }

    /// The native `getPreSignedInputData(incrementNonce:)` overload must bump the
    /// nonce by exactly 1 (nonce N → N+1) and otherwise produce a different hash.
    /// This is the primitive the non-swap approve bundle relies on to land the
    /// deposit at N+1.
    func testNativeMemoCallIncrementNonceBumpsByOne() throws {
        let eth = try ethCoin()
        let helper = EVMHelper(coinType: .ethereum)

        // nonce N=5 with increment must equal nonce N=6 without increment.
        let atFive = makeNativeMemoCallPayload(coin: eth, nonce: 5, approve: nil)
        let atSix = makeNativeMemoCallPayload(coin: eth, nonce: 6, approve: nil)

        let incremented = try helper.getPreSignedImageHash(keysignPayload: atFive, incrementNonce: true)
        let plain = try helper.getPreSignedImageHash(keysignPayload: atSix, incrementNonce: false)
        XCTAssertEqual(incremented, plain, "incrementNonce on nonce N must equal a plain build at nonce N+1")

        // And it must differ from the same-nonce plain build.
        let plainAtFive = try helper.getPreSignedImageHash(keysignPayload: atFive, incrementNonce: false)
        XCTAssertNotEqual(incremented, plainAtFive, "incrementNonce must change the signed bytes")
    }

    /// Funds-safety pin: a non-swap approve bundle on a native EVM coin must yield
    /// EXACTLY two messages — approve at nonce N and the memo call at nonce N+1.
    /// If it ever collapses to one, the deposit would be silently dropped.
    func testNonSwapApproveBundleYieldsTwoMessages() throws {
        let eth = try ethCoin()
        let approve = ERC20ApprovePayload(
            amount: BigInt(100_000_000),
            spender: "0xA73424f1Ac94b3ef0D0c9af4F2967c87D4AF25D9",
            token: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
        )
        let payload = makeNativeMemoCallPayload(coin: eth, nonce: 7, approve: approve)

        let messages = try KeysignMessageFactory(payload: payload).getKeysignMessages()
        XCTAssertEqual(messages.count, 2, "non-swap approve bundle must be [approve@N, call@N+1]")

        // The second message must be the memo call at nonce N+1.
        let helper = EVMHelper(coinType: .ethereum)
        let mainAtNPlus1 = try helper.getPreSignedImageHash(keysignPayload: payload, incrementNonce: true)
        XCTAssertEqual(messages[1], mainAtNPlus1[0], "the deposit leg must sign at nonce N+1")

        // The first message must be the approve, targeting the explicit token.
        let approveHash = try THORChainSwaps().getPreSignedApproveImageHash(approvePayload: approve, keysignPayload: payload)
        XCTAssertEqual(messages[0], approveHash[0], "the approve leg must sign at nonce N")
    }

    /// The approve token fallback: an empty `token` targets the keysign coin's
    /// contract (swap-approve behaviour, unchanged); a non-empty `token` targets
    /// that contract instead. Pinning both keeps swap approves byte-identical.
    func testApproveTokenFallback() throws {
        let usdc = try CoinFactory.create(
            asset: CoinMeta(
                chain: .ethereum,
                ticker: "USDC",
                logo: "usdc",
                decimals: 6,
                priceProviderId: "usd-coin",
                contractAddress: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                isNativeToken: false
            ),
            publicKeyECDSA: hexPublicKey,
            publicKeyEdDSA: "",
            hexChainCode: hexChainCode,
            isDerived: false
        )
        let swaps = THORChainSwaps()

        // Empty token on a USDC keysign → approve targets USDC (coin contract).
        let emptyTokenPayload = makeNativeMemoCallPayload(
            coin: usdc, nonce: 0,
            approve: ERC20ApprovePayload(amount: BigInt(1), spender: "0xA73424f1Ac94b3ef0D0c9af4F2967c87D4AF25D9")
        )
        let coinFallbackHash = try swaps.getPreSignedApproveImageHash(
            approvePayload: ERC20ApprovePayload(amount: BigInt(1), spender: "0xA73424f1Ac94b3ef0D0c9af4F2967c87D4AF25D9"),
            keysignPayload: emptyTokenPayload
        )
        // Explicit token == coin contract must reproduce the same bytes.
        let explicitSameHash = try swaps.getPreSignedApproveImageHash(
            approvePayload: ERC20ApprovePayload(amount: BigInt(1), spender: "0xA73424f1Ac94b3ef0D0c9af4F2967c87D4AF25D9", token: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"),
            keysignPayload: emptyTokenPayload
        )
        XCTAssertEqual(coinFallbackHash, explicitSameHash, "empty token must fall back to the coin contract")

        // A DIFFERENT explicit token must change the approve bytes.
        let otherTokenHash = try swaps.getPreSignedApproveImageHash(
            approvePayload: ERC20ApprovePayload(amount: BigInt(1), spender: "0xA73424f1Ac94b3ef0D0c9af4F2967c87D4AF25D9", token: "0x6b175474e89094c44da98b954eedeac495271d0f"),
            keysignPayload: emptyTokenPayload
        )
        XCTAssertNotEqual(coinFallbackHash, otherTokenHash, "an explicit token must change the approve target")
    }
}
