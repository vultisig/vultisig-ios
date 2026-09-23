//
//  BalanceServiceMulticallProbeCacheTests.swift
//  VultisigAppTests
//
//  Covers the caching rules of the runtime Multicall3 code probe: a definitive
//  code / no-code answer is kept for the life of the service, a failed probe is
//  not, so the next refresh retries instead of pinning the chain to the slow
//  per-coin path.
//

@testable import VultisigApp
import XCTest

final class BalanceServiceMulticallProbeCacheTests: XCTestCase {

    private struct ProbeFailure: Error {}

    private let deployedCode = "0x6080604052"

    func testChainWithoutRuntimeGateIsTrustedWithoutProbing() async {
        let service = BalanceService()
        var probes = 0

        let available = await service.isMulticallAvailable(chain: .ethereum) {
            probes += 1
            return "0x"
        }

        XCTAssertTrue(available)
        XCTAssertEqual(probes, 0)
    }

    func testDeployedContractIsCachedAfterOneProbe() async {
        let service = BalanceService()
        var probes = 0

        let first = await service.isMulticallAvailable(chain: .hyperliquid) {
            probes += 1
            return self.deployedCode
        }
        let second = await service.isMulticallAvailable(chain: .hyperliquid) {
            probes += 1
            throw ProbeFailure()
        }

        XCTAssertTrue(first)
        XCTAssertTrue(second)
        XCTAssertEqual(probes, 1)
    }

    func testMissingContractIsCachedAfterOneProbe() async {
        let service = BalanceService()
        var probes = 0

        let first = await service.isMulticallAvailable(chain: .hyperliquid) {
            probes += 1
            return "0x"
        }
        let second = await service.isMulticallAvailable(chain: .hyperliquid) {
            probes += 1
            return self.deployedCode
        }

        XCTAssertFalse(first)
        XCTAssertFalse(second)
        XCTAssertEqual(probes, 1)
    }

    func testFailedProbeIsNotCachedSoTheNextCallRetries() async {
        let service = BalanceService()
        var probes = 0

        let first = await service.isMulticallAvailable(chain: .hyperliquid) {
            probes += 1
            throw ProbeFailure()
        }
        let second = await service.isMulticallAvailable(chain: .hyperliquid) {
            probes += 1
            return self.deployedCode
        }

        XCTAssertFalse(first)
        XCTAssertTrue(second)
        XCTAssertEqual(probes, 2)
    }
}
