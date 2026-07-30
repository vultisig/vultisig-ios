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
/// This list — not a wildcard walk of the bundle — is what the suite executes.
/// A wildcard walk is what let the entire corpus stop running without anything
/// turning red: the walk's "is this one of ours?" filter silently matched
/// nothing, so the loop body never ran and the suite stayed green with zero
/// conformance coverage.
///
/// Two tests keep that from happening again.
/// `testAllRegisteredFixturesExecute` runs every case in this list in a single
/// test and pins the total vector count, so coverage never depends on
/// per-method bookkeeping and cannot shrink unnoticed;
/// `testEveryBundledFixtureIsRegistered` pins the list against the JSON files
/// actually present in the bundle — in both directions — so a fixture can
/// neither be added without being run nor listed without existing.
///
/// ## Provenance of the expected hashes
///
/// A vector is only worth anything if its `expected_image_hash` was produced by
/// more than one implementation. A hash captured from a single signer proves
/// that signer is self-consistent and nothing more — it silently promotes that
/// signer's bugs to ground truth, which is the failure mode the corpus exists
/// to catch.
///
/// What agreement between two implementations does and does not establish is
/// worth being exact about. All three platform signers build a protobuf signing
/// input themselves and then hand it to the same WalletCore compiler, so two of
/// them agreeing pins **the platform-specific construction layer** — chain IDs,
/// transaction envelope, message shape, denoms, fee fields — which is where the
/// cross-platform keysign failures this corpus exists for actually originate.
/// It does **not** independently verify WalletCore itself: a bug inside the
/// shared compiler would be invisible to every one of these vectors.
///
/// - `evm-chain-matrix` and `tcy` were added by running the Swift signer and
///   the TypeScript core signer over the identical payload and requiring the
///   two to produce byte-identical hashes.
/// - Every other case here is also carried by vultisig-android (and, for the
///   `cosmos-sdk-sign-*` cases, by the TypeScript core), so those hashes too
///   carry agreement from at least two signers — **with one known exception**:
///   `cosmos-sdk-sign-amino.json` → "SignAmino - THORChain transaction memo"
///   appears in no other corpus and has only ever been produced by the Swift
///   signer. It is left in place because removing coverage is worse than
///   flagging it, but it is not corroborated and should not be treated as
///   ground truth until a second signer reproduces it.
///
/// `evm-chain-matrix` reuses one payload across chains: every field that feeds
/// the EVM pre-image — recipient, amount, nonce, gas limit and fee fields — is
/// held identical, and only `coin.chain` varies. The remaining differences are
/// that chain's real native-asset metadata (`ticker`, `logo`), which the EVM
/// signing input never reads. Every case must therefore still hash differently,
/// because the EIP-155 chain ID *is* part of the signed pre-image — which is
/// what lets these vectors catch a per-chain chain-ID regression.
enum ChainHelperFixture: String, CaseIterable {
    case arb
    case bsc
    case cardano
    case cosmos
    case cosmosSdkSignAmino = "cosmos-sdk-sign-amino"
    case cosmosSdkSignDirect = "cosmos-sdk-sign-direct"
    case dot
    case evm
    case evmChainMatrix = "evm-chain-matrix"
    case kujira
    case lifiswap
    case maya
    case mayaswap
    case pol
    case solana
    case solanaSignData = "solana-sign-data"
    case sui
    case tcy
    case terra
    case thorchain
    case thorchainswap
    case ton
    case tron
    case utxo
    case xrp

    /// How many signing vectors this fixture must contain.
    ///
    /// Pinning the count is what stops the corpus shrinking quietly: the
    /// filename checks only prove the file still exists, not that it still
    /// asserts anything, and a fixture emptied down to one vector would
    /// otherwise stay green. Adding or removing a vector is a deliberate act,
    /// so it should show up here as a deliberate edit.
    var expectedCaseCount: Int {
        switch self {
        case .arb: return 1
        case .bsc: return 2
        case .cardano: return 2
        case .cosmos: return 4
        case .cosmosSdkSignAmino: return 2
        case .cosmosSdkSignDirect: return 2
        case .dot: return 1
        case .evm: return 2
        case .evmChainMatrix: return 8
        case .kujira: return 3
        case .lifiswap: return 2
        case .maya: return 3
        case .mayaswap: return 2
        case .pol: return 1
        case .solana: return 4
        case .solanaSignData: return 1
        case .sui: return 1
        case .tcy: return 2
        case .terra: return 5
        case .thorchain: return 9
        case .thorchainswap: return 5
        case .ton: return 3
        case .tron: return 4
        case .utxo: return 5
        case .xrp: return 3
        }
    }

    /// The per-fixture test method that must exist so a failure is attributable
    /// to one fixture instead of to the corpus as a whole. Derived from the
    /// file name, so the guard checks the same name the method has to declare.
    var testMethodName: String {
        let camelCased = rawValue
            .split(separator: "-")
            .enumerated()
            .map { $0.offset == 0 ? String($0.element) : $0.element.capitalized }
            .joined()
        return "test\(camelCased.prefix(1).uppercased())\(camelCased.dropFirst())Fixture"
    }
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
    func testEvmChainMatrixFixture() throws { try runFixture(.evmChainMatrix) }
    func testKujiraFixture() throws { try runFixture(.kujira) }
    func testLifiswapFixture() throws { try runFixture(.lifiswap) }
    func testMayaFixture() throws { try runFixture(.maya) }
    func testMayaswapFixture() throws { try runFixture(.mayaswap) }
    func testPolFixture() throws { try runFixture(.pol) }
    func testSolanaFixture() throws { try runFixture(.solana) }
    func testSolanaSignDataFixture() throws { try runFixture(.solanaSignData) }
    func testSuiFixture() throws { try runFixture(.sui) }
    func testTcyFixture() throws { try runFixture(.tcy) }
    func testTerraFixture() throws { try runFixture(.terra) }
    func testThorchainFixture() throws { try runFixture(.thorchain) }
    func testThorchainswapFixture() throws { try runFixture(.thorchainswap) }
    func testTonFixture() throws { try runFixture(.ton) }
    func testTronFixture() throws { try runFixture(.tron) }
    func testUtxoFixture() throws { try runFixture(.utxo) }
    func testXrpFixture() throws { try runFixture(.xrp) }

    // MARK: - Corpus guards

    /// Authoritative coverage: executes every registered fixture in one test.
    ///
    /// The per-fixture methods above exist for attribution, but coverage must
    /// not depend on someone remembering to add one — that bookkeeping is
    /// exactly what failed before. This test runs the whole registered corpus
    /// regardless of how many per-fixture methods survive, so the vectors
    /// cannot go dark again. Cases therefore run twice; the corpus is small
    /// enough that this costs a fraction of a second.
    func testAllRegisteredFixturesExecute() throws {
        var executedCases = 0
        for fixture in ChainHelperFixture.allCases {
            executedCases += try runFixture(fixture)
        }

        let expectedCases = ChainHelperFixture.allCases.reduce(0) { $0 + $1.expectedCaseCount }
        XCTAssertEqual(executedCases, expectedCases,
                       "The golden corpus executed \(executedCases) signing vectors, expected \(expectedCases) — coverage shrank")
    }

    /// Every EVM native send must produce a different pre-image hash, and the
    /// hashes are **recomputed here from the payloads** rather than read back
    /// out of the fixtures.
    ///
    /// Those payloads hold every pre-image-feeding field identical and vary
    /// only `coin.chain` (plus native-asset metadata the EVM signing input does
    /// not read), so the only thing that can separate their pre-images is the
    /// EIP-155 chain ID. If a chain ever stopped contributing its own — by
    /// falling back to the WalletCore coin type's default, which is what makes
    /// chains sharing a coin type dangerous — two would collapse onto the same
    /// hash. Each vector on its own would still pass, since each is only
    /// compared against its own committed value; only the relationship between
    /// them exposes it.
    ///
    /// Reading `expected_image_hash` here instead would make this test
    /// self-satisfying: any set of distinct strings would pass it, including
    /// one re-baselined around the very regression it is meant to catch. It
    /// therefore drives the real signers through `computeDirectImageHashes`.
    func testEvmChainMatrixVectorsAreChainSpecific() throws {
        var computedHashesByCase: [String: [String]] = [:]

        for fixture in [ChainHelperFixture.evmChainMatrix, .evm] {
            for testCase in try decodeFixture(fixture) where testCase.keysignPayload.coin.isNativeToken {
                let keysignPayload = try KeysignPayload(proto: testCase.keysignPayload)
                XCTAssertEqual(keysignPayload.coin.chainType, .EVM,
                               "\(testCase.name) is not an EVM payload, so it does not belong in this check")
                computedHashesByCase[testCase.name] = try computeDirectImageHashes(keysignPayload: keysignPayload)
            }
        }

        XCTAssertEqual(computedHashesByCase.count, ChainHelperFixture.evmChainMatrix.expectedCaseCount + 1,
                       "Expected every EVM matrix case plus the Ethereum native send to take part in this check, got \(computedHashesByCase.keys.sorted())")

        let allHashes = computedHashesByCase.values.flatMap { $0 }
        XCTAssertEqual(allHashes.count, computedHashesByCase.count,
                       "Every EVM native send should produce exactly one pre-image hash")
        XCTAssertEqual(Set(allHashes).count, allHashes.count,
                       "Two EVM native sends computed the same pre-image hash. Their payloads differ only by chain, so a chain has stopped contributing its own EIP-155 chain ID: \(computedHashesByCase)")
    }

    /// Fails if the bundled corpus and the registered fixtures diverge in
    /// either direction, or if a fixture has lost its attributing test method.
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
                       "Bundled golden fixtures missing from ChainHelperFixture — add the case and its test method")
        XCTAssertEqual(registered.subtracting(bundled), [],
                       "Registered golden fixtures missing from the bundle")

        let discoveredTestNames = Self.defaultTestSuite.tests.map(\.name)
        for fixture in ChainHelperFixture.allCases {
            XCTAssertTrue(discoveredTestNames.contains { $0.contains(fixture.testMethodName) },
                          "Golden fixture \(fixture.rawValue).json has no \(fixture.testMethodName)() method, so its failures would not be attributable to it")
        }
    }

    // MARK: - Runner

    private enum FixtureError: Error, CustomStringConvertible {
        case missing(String, subdirectory: String)
        case undecodable(String, underlying: Error)

        var description: String {
            switch self {
            case .missing(let name, let subdirectory):
                return "Missing golden fixture \(subdirectory)/\(name).json in the test bundle"
            case .undecodable(let name, let underlying):
                return "Invalid golden fixture \(name).json: \(underlying)"
            }
        }
    }

    /// Loads and decodes one fixture without running it.
    private func decodeFixture(_ fixture: ChainHelperFixture) throws -> [ChainHelperTestCase] {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: fixture.rawValue,
                                   withExtension: "json",
                                   subdirectory: Self.fixtureSubdirectory) else {
            throw FixtureError.missing(fixture.rawValue, subdirectory: Self.fixtureSubdirectory)
        }

        do {
            return try JSONDecoder().decode([ChainHelperTestCase].self, from: try Data(contentsOf: url))
        } catch {
            throw FixtureError.undecodable(fixture.rawValue, underlying: error)
        }
    }

    /// Runs one fixture and returns the number of cases it executed.
    @discardableResult
    private func runFixture(_ fixture: ChainHelperFixture,
                            file: StaticString = #filePath,
                            line: UInt = #line) throws -> Int {
        let testCases: [ChainHelperTestCase]
        do {
            testCases = try decodeFixture(fixture)
        } catch {
            XCTFail("\(error)", file: file, line: line)
            return 0
        }

        XCTAssertEqual(testCases.count, fixture.expectedCaseCount,
                       "Golden fixture \(fixture.rawValue).json holds \(testCases.count) signing vectors, expected \(fixture.expectedCaseCount) — if a vector was deliberately added or removed, update ChainHelperFixture.expectedCaseCount",
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

        return testCases.count
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
        let result = try computeDirectImageHashes(keysignPayload: keysignPayload)
        XCTAssertEqual(result, testCase.expectedImageHash, "Test case \(testCase.name) failed for \(chain.name)")
    }

    /// Computes the pre-signing image hash for a non-swap payload by dispatching
    /// to the same per-chain signer the app uses.
    ///
    /// Separated from `runTestCase` so a test can obtain a *computed* hash
    /// rather than the committed one. A guard that reasons about the corpus by
    /// reading `expected_image_hash` back out of the JSON proves nothing about
    /// the signers — it would be satisfied by any set of distinct strings.
    private func computeDirectImageHashes(keysignPayload: KeysignPayload) throws -> [String] {
        let chain = keysignPayload.coin.chain
        var result: [String] = []
        switch chain {
        case .bitcoin, .bitcoinCash, .dogecoin, .litecoin, .zcash:
            let utxoHelper = UTXOChainsHelper(coin: chain.coinType)
            let imageHash = try utxoHelper.getPreSignedImageHash(keysignPayload: keysignPayload)
            result += imageHash
        case .ethereum, .arbitrum, .optimism, .polygon, .base, .bscChain, .avalanche, .mantle,
             .blast, .cronosChain, .zksync, .hyperliquid:
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

        return result
    }
}
