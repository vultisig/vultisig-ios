//
//  ERC20Test.swift
//  VultisigApp
//
//  Created by Johnny Luo on 27/9/2024.
//

@testable import VultisigApp
import WalletCore
import XCTest
import BigInt

final class ERC20ChainsHelperTest: XCTestCase {
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
        let usdc = try CoinFactory.create(
            asset: TokensStore.Token.ethereumUsdc,
            publicKeyECDSA: hexPublicKey,
            publicKeyEdDSA: "",
            hexChainCode: hexChainCode,
            isDerived: false
        )
        let keysignPayload = KeysignPayload(
            coin: usdc,
            toAddress: "0xfA0635a1d083D0bF377EFbD48DA46BB17e0106cA",
            toAmount: 10000000,
            chainSpecific: BlockChainSpecific.Ethereum(
                maxFeePerGasWei: BigInt(10),
                priorityFeeWei: BigInt(1),
                nonce: 0,
                gasLimit: BigInt(120000)
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
        let eRC20Helper = ERC20Helper(coinType: .ethereum)
        let preImageHashes = try eRC20Helper.getPreSignedImageHash(keysignPayload: keysignPayload)
        XCTAssertEqual(preImageHashes.count,1)
        XCTAssertEqual(preImageHashes[0],"5ac8a3ccea00ecdb506d387424d68390d94623431798a2f65903aea1d6cf13c9")
    }
}
