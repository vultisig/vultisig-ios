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

/// The golden signing-vector fixtures bundled under `TestData/`.
///
/// Every fixture is named here and gets its own `test…` method rather than
/// being discovered by a wildcard walk of the bundle. A wildcard walk is what
/// let the entire corpus stop executing without anything turning red: the
/// walk's "is this one of ours?" filter silently matched nothing, so the loop
/// body never ran and the suite stayed green with zero conformance coverage.
///
/// Explicit registration makes that failure mode impossible to reach silently:
/// `testEveryBundledFixtureIsRegistered` pins this list against the JSON files
/// actually present in the bundle and against the number of test methods on
/// this class, so a fixture can neither be added without a test nor listed
/// without one.
enum ChainHelperFixture: String, CaseIterable {
    case arb
    case bsc
    case cardano
    case cosmos
    case cosmosSdkSignAmino = "cosmos-sdk-sign-amino"
    case cosmosSdkSignDirect = "cosmos-sdk-sign-direct"
    case dot
    case evm
    case kujira
    case lifiswap
    case maya
    case mayaswap
    case pol
    case solana
    case solanaSignData = "solana-sign-data"
    case sui
    case terra
    case thorchain
    case thorchainswap
    case ton
    case tron
    case utxo
    case xrp
}

final class ChainHelperTests: XCTestCase {
    let hexPublicKey = "023e4b76861289ad4528b33c2fd21b3a5160cd37b3294234914e21efb6ed4a452b"
    let hexChainCode = "c9b189a8232b872b8d9ccd867d0db316dd10f56e729c310fe072adf5fd204ae7"

    /// Fixtures are bundled as a folder reference so they keep their own
    /// directory inside the test bundle instead of flattening into the
    /// resource root next to unrelated suites' JSON.
    private static let fixtureSubdirectory = "TestData"

    // MARK: - Per-fixture golden vectors

    func testArbFixture() throws { try runFixture(.arb) }
    func testBscFixture() throws { try runFixture(.bsc) }
    func testCardanoFixture() throws { try runFixture(.cardano) }
    func testCosmosFixture() throws { try runFixture(.cosmos) }
    func testCosmosSdkSignAminoFixture() throws { try runFixture(.cosmosSdkSignAmino) }
    func testCosmosSdkSignDirectFixture() throws { try runFixture(.cosmosSdkSignDirect) }
    func testDotFixture() throws { try runFixture(.dot) }
    func testEvmFixture() throws { try runFixture(.evm) }
    func testKujiraFixture() throws { try runFixture(.kujira) }
    func testLifiswapFixture() throws { try runFixture(.lifiswap) }
    func testMayaFixture() throws { try runFixture(.maya) }
    func testMayaswapFixture() throws { try runFixture(.mayaswap) }
    func testPolFixture() throws { try runFixture(.pol) }
    func testSolanaFixture() throws { try runFixture(.solana) }
    func testSolanaSignDataFixture() throws { try runFixture(.solanaSignData) }
    func testSuiFixture() throws { try runFixture(.sui) }
    func testTerraFixture() throws { try runFixture(.terra) }
    func testThorchainFixture() throws { try runFixture(.thorchain) }
    func testThorchainswapFixture() throws { try runFixture(.thorchainswap) }
    func testTonFixture() throws { try runFixture(.ton) }
    func testTronFixture() throws { try runFixture(.tron) }
    func testUtxoFixture() throws { try runFixture(.utxo) }
    func testXrpFixture() throws { try runFixture(.xrp) }

    // MARK: - Corpus guard

    /// Fails if the bundled corpus and the registered fixtures diverge in
    /// either direction, so no fixture can silently stop being executed.
    func testEveryBundledFixtureIsRegistered() throws {
        let bundle = Bundle(for: type(of: self))
        guard let urls = bundle.urls(forResourcesWithExtension: "json",
                                     subdirectory: Self.fixtureSubdirectory) else {
            XCTFail("No \(Self.fixtureSubdirectory) directory in the test bundle — the golden fixtures are not being copied as resources")
            return
        }

        let bundled = Set(urls.map { $0.deletingPathExtension().lastPathComponent })
        let registered = Set(ChainHelperFixture.allCases.map(\.rawValue))

        XCTAssertEqual(bundled.subtracting(registered), [],
                       "Bundled golden fixtures with no test method — add a case to ChainHelperFixture and a test that runs it")
        XCTAssertEqual(registered.subtracting(bundled), [],
                       "Registered golden fixtures missing from the bundle")

        // One `test…Fixture` method per registered fixture, plus this guard.
        XCTAssertEqual(Self.defaultTestSuite.testCaseCount, ChainHelperFixture.allCases.count + 1,
                       "Every ChainHelperFixture case needs its own test method so failures are attributable per fixture")
    }

    // MARK: - Runner

    private func runFixture(_ fixture: ChainHelperFixture,
                            file: StaticString = #filePath,
                            line: UInt = #line) throws {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: fixture.rawValue,
                                   withExtension: "json",
                                   subdirectory: Self.fixtureSubdirectory) else {
            XCTFail("Missing golden fixture \(Self.fixtureSubdirectory)/\(fixture.rawValue).json in the test bundle",
                    file: file, line: line)
            return
        }

        let data = try Data(contentsOf: url)
        let testCases: [ChainHelperTestCase]
        do {
            testCases = try JSONDecoder().decode([ChainHelperTestCase].self, from: data)
        } catch {
            XCTFail("Invalid golden fixture \(fixture.rawValue).json: \(error)", file: file, line: line)
            return
        }

        XCTAssertFalse(testCases.isEmpty,
                       "Golden fixture \(fixture.rawValue).json decoded to zero cases",
                       file: file, line: line)

        // Run every case even if an earlier one throws, so one broken vector
        // doesn't hide the state of the rest of the file.
        for testCase in testCases {
            do {
                try runTestCase(testCase)
            } catch {
                XCTFail("Test case \(testCase.name) threw: \(error)", file: file, line: line)
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
        case .thorchain(let swapPayload), .thorchainChainnet(let swapPayload), .thorchainStagenet(let swapPayload):
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
        case .swapkit:
            // Phase 2 fixtures don't exercise the SwapKit BTC PSBT signing
            // path yet — that lands in a follow-up alongside the actual
            // per-chain signer wiring in `UTXOChainsHelper`. Surface a
            // failure so the gap is visible if a future test case starts
            // shipping a `.swapkit` swap payload through this runner.
            XCTFail("SwapKit swap payload not yet handled by this test runner — \(testCase.name)")
        case .none:
            XCTFail("Swap payload is nil for test case \(testCase.name)")
        }
        XCTAssertEqual(result, testCase.expectedImageHash, "Test case \(testCase.name) failed")
    }

    private func runTestCase(_ testCase: ChainHelperTestCase) throws {
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
        case .cardano:
            keysignPayload.coin.rawBalance = keysignPayload.toAmount.description
            result += try CardanoHelper.getPreSignedImageHash(keysignPayload: keysignPayload)
        default:
            XCTFail("Unsupported chain: \(String(describing: chain.name))")
        }

        XCTAssertEqual(result, testCase.expectedImageHash, "Test case \(testCase.name) failed for \(chain.name)")
    }
}
