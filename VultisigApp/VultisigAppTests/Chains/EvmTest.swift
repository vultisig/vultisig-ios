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
            skipBroadcast: false,
            signData: nil
        )
        let evmHelper = EVMHelper(coinType: .ethereum)
        let preImageHashes = try evmHelper.getPreSignedImageHash(keysignPayload: keysignPayload)
        XCTAssertEqual(preImageHashes.count,1)
        XCTAssertEqual(preImageHashes[0],"1e93ef6b20b01723e95128aed8786d43c7c53a12959a21ef36cf408a6d7115de")
    }
}
