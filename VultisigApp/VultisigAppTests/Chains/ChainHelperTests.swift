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
        // Get the test bundle
        let bundle = Bundle(for: type(of: self))

        // Get all JSON files in the bundle
        let fileManager = FileManager.default
        guard let resourcePath = bundle.resourcePath else {
            XCTFail("Missing resource path")
            return
        }
        let resourceURL = URL(fileURLWithPath: resourcePath)
        let jsonFiles = try fileManager.contentsOfDirectory(at: resourceURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }

        // Iterate through each JSON file
        for jsonFile in jsonFiles {
            let data = try Data(contentsOf: jsonFile)
            let decoder = JSONDecoder()
            let testCases = try decoder.decode([ChainHelperTestCase].self, from: data)

            for testCase in testCases {
                try runTestCase(testCase)
            }
        }

    }
    private func runTestCaseWithSwap(_ testCase: ChainHelperTestCase, keysignPayload: KeysignPayload) throws {
        var result: [String] = []
        if keysignPayload.approvePayload != nil {
            let swaps = THORChainSwaps()
            let approvalImageHash = try swaps.getPreSignedApproveImageHash(approvePayload: keysignPayload.approvePayload!, keysignPayload: keysignPayload)
            result += approvalImageHash
        }
        let incrementNonce = keysignPayload.approvePayload != nil
        switch keysignPayload.swapPayload {
        case .thorchain(let swapPayload), .thorchainStagenet(let swapPayload):
            let swaps = THORChainSwaps()
            let imageHash = try swaps.getPreSignedImageHash(swapPayload: swapPayload,
                                                            keysignPayload: keysignPayload,
                                                            incrementNonce: incrementNonce)
            result += imageHash
        case .mayachain(let swapPayload):
            let swaps = THORChainSwaps()
            let imageHash = try swaps.getPreSignedImageHash(swapPayload: swapPayload,
                                                            keysignPayload: keysignPayload,
                                                            incrementNonce: incrementNonce)
            result += imageHash

        case .generic(let oneInchSwapPayload):
            switch keysignPayload.coin.chain {
            case .solana:
                let swaps = SolanaSwaps()
                result += try swaps.getPreSignedImageHash(swapPayload: oneInchSwapPayload, keysignPayload: keysignPayload)
            default:
                let swaps = OneInchSwaps()
                result += try swaps.getPreSignedImageHash(payload: oneInchSwapPayload, keysignPayload: keysignPayload, incrementNonce: incrementNonce)
            }
        case .none:
            XCTFail("Swap payload is nil for test case \(testCase.name)")
        }
        XCTAssertEqual(result, testCase.expectedImageHash, "Test case \(testCase.name) failed")
    }
    private func runTestCase(_ testCase: ChainHelperTestCase) throws {
        print("Running test case: \(testCase.name)")
        let keysignPayload = try KeysignPayload(proto: testCase.keysignPayload)
        let chain = keysignPayload.coin.chain
        if keysignPayload.swapPayload != nil {
            switch keysignPayload.swapPayload {
            case .mayachain:
                if keysignPayload.coin.chainType == .EVM  && !keysignPayload.coin.isNativeToken {
                    try runTestCaseWithSwap(testCase, keysignPayload: keysignPayload)
                    return
                }
            default:
                try runTestCaseWithSwap(testCase, keysignPayload: keysignPayload)
                return
            }
        }
        var result: [String] = []
        switch chain {
        case .bitcoin, .bitcoinCash, .dogecoin, .litecoin, .zcash:
            let utxoHelper = UTXOChainsHelper(coin: chain.coinType)
            let imageHash = try utxoHelper.getPreSignedImageHash(keysignPayload: keysignPayload)
            result += imageHash
        case .ethereum, .arbitrum, .optimism, .polygon, .base, .bscChain, .avalanche, .mantle:
            let chain = keysignPayload.coin.chain
            if keysignPayload.coin.contractAddress.isEmpty {
                let evmHelper = EVMHelper.getHelper(coin: keysignPayload.coin)
                let imageHash = try evmHelper.getPreSignedImageHash(keysignPayload: keysignPayload)
                result += imageHash
            } else {
                let erc20Helper = ERC20Helper(coinType: chain.coinType)
                let imageHash = try erc20Helper.getPreSignedImageHash(keysignPayload: keysignPayload)
                result += imageHash
            }
        case .thorChain:
            let imageHash = try THORChainHelper.getPreSignedImageHash(keysignPayload: keysignPayload)
            result += imageHash
        case .mayaChain:
            result += try MayaChainHelper.getPreSignedImageHash(keysignPayload: keysignPayload)
        case .solana:
            result +=  try SolanaHelper.getPreSignedImageHash(keysignPayload: keysignPayload)
        case .ripple:
            result += try RippleHelper.getPreSignedImageHash(keysignPayload: keysignPayload)
        case .terra, .terraClassic, .gaiaChain, .kujira:
            let helper = try CosmosHelper.getHelper(forChain: chain)
            result += try helper.getPreSignedImageHash(keysignPayload: keysignPayload)
        case .ton:
            result += try TonHelper.getPreSignedImageHash(keysignPayload: keysignPayload)
        case .tron:
            result += try TronHelper.getPreSignedImageHash(keysignPayload: keysignPayload)
        case .polkadot:
            result += try PolkadotHelper.getPreSignedImageHash(keysignPayload: keysignPayload)
        case .sui:
            result += try SuiHelper.getPreSignedImageHash(keysignPayload: keysignPayload)
        default:
            XCTFail("Unsupported chain: \(String(describing: chain.name))")
        }

        XCTAssertEqual(result, testCase.expectedImageHash, "Test case \(testCase.name) failed for \(chain.name)")
    }
}
