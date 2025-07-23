//
//  CahinHelperTests.swift
//  VultisigApp
//
//  Created by Johnny Luo on 23/7/2025.
//

@testable import VultisigApp
import VultisigCommonData
import XCTest
import Foundation

struct ChainHelperTestCase: Codable {
    let name: String
    let keysignPayload: VSKeysignPayload // base64 encoded JSON string of KeysignPayload
    let expectedImageHash: String

    enum CodingKeys: String, CodingKey {
        case name
        case keysignPayload = "keysign_payload"
        case expectedImageHash = "expected_image_hash"
    }
    
    init(name: String, keysignPayload: VSKeysignPayload, expectedImageHash: String) {
        self.name = name
        self.keysignPayload = keysignPayload
        self.expectedImageHash = expectedImageHash
    }
    
}

final class ChainHelperTests: XCTestCase {
    let hexPublicKey = "023e4b76861289ad4528b33c2fd21b3a5160cd37b3294234914e21efb6ed4a452b"
    let hexChainCode = "c9b189a8232b872b8d9ccd867d0db316dd10f56e729c310fe072adf5fd204ae7"
    
    func testCreateJson() throws {
        let vaultForTest = Vault(name: "TestVault")
        vaultForTest.pubKeyECDSA = hexPublicKey
        vaultForTest.hexChainCode = hexChainCode
        let btc = try CoinFactory.create(asset: TokensStore.Token.bitcoin, vault: vaultForTest)
        let keysignPayload = KeysignPayload(coin: btc,
                                            toAddress: "bc1q4e4y3g85dtkx0yp3l2flj2nmugf23c9wwtjwu5",
                                            toAmount: 10000000,
                                            chainSpecific: BlockChainSpecific.UTXO(byteFee: 20,sendMaxAmount: false),
                                            utxos: [UtxoInfo(hash: "631fad872ac6bea810cf6073f02e6cbd121cac83193b79f381f711ce93b531f0", amount: 193796, index: 1)],
                                            memo: "voltix",
                                            swapPayload: nil,
                                            approvePayload: nil,
                                            vaultPubKeyECDSA: "ECDSAKey",
                                            vaultLocalPartyID: "localPartyID",
                                            libType: LibType.DKLS.toString())
        
        let testcase = ChainHelperTestCase(
            name: "Normal Bitcoin Send",
            keysignPayload: keysignPayload.mapToProtobuff(),
            expectedImageHash:  "b3f9a6c8c7b5e2d9f0e1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f"
        )
        let encoder = JSONEncoder()
        let result = try encoder.encode([testcase])
        let jsonString = String(data: result, encoding: .utf8)!
        print("JSON String: \(jsonString)")
    }
}
