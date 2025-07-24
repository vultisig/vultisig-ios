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
    let expectedImageHash: [String]

    enum CodingKeys: String, CodingKey {
        case name
        case keysignPayload = "keysign_payload"
        case expectedImageHash = "expected_image_hash"
    }
}

final class ChainHelperTests: XCTestCase {
    let hexPublicKey = "023e4b76861289ad4528b33c2fd21b3a5160cd37b3294234914e21efb6ed4a452b"
    let hexChainCode = "c9b189a8232b872b8d9ccd867d0db316dd10f56e729c310fe072adf5fd204ae7"
    
    func testChainHelpers() throws {
        // Locate the JSON file in the test bundle
        guard let url = Bundle(for: type(of: self)).url(forResource: "testdata", withExtension: "json") else {
            XCTFail("Missing file: testdata.json")
            return
        }
        
        // Load the JSON data
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let testCases = try decoder.decode([ChainHelperTestCase].self, from: data)
        for (_,tc) in testCases.enumerated() {
            try runTestCase(tc)
        }
    }
    
    private func runTestCase(_ testCase: ChainHelperTestCase) throws {
        let keysignPayload = try KeysignPayload(proto: testCase.keysignPayload)
        let chain = keysignPayload.coin.chain
        switch chain {
        case .bitcoin,.bitcoinCash,.dogecoin,.litecoin,.zcash:
            let utxoHelper = UTXOChainsHelper(coin: chain.coinType, vaultHexPublicKey: hexPublicKey, vaultHexChainCode: hexChainCode)
            let result = try utxoHelper.getPreSignedImageHash(keysignPayload: keysignPayload)
            XCTAssertEqual(result, testCase.expectedImageHash, "Test case \(testCase.name) failed for \(chain.name)")
        
        case .ethereum:
            let chain = keysignPayload.coin.chain
            if keysignPayload.coin.contractAddress.isEmpty {
                let evmHelper = EVMHelper.getHelper(coin: keysignPayload.coin)
                let result = try evmHelper.getPreSignedImageHash(keysignPayload: keysignPayload)
                XCTAssertEqual(result, testCase.expectedImageHash, "Test case \(testCase.name) failed for \(chain.name)")
            } else {
                let erc20Helper = ERC20Helper(coinType: chain.coinType)
                let result = try erc20Helper.getPreSignedImageHash(keysignPayload: keysignPayload)
                XCTAssertEqual(result, testCase.expectedImageHash, "Test case \(testCase.name) failed for ERC20 on \(chain.name)")
            }
        default:
            XCTFail("Unsupported chain: \(String(describing: chain.name))")
        }
    }
}

