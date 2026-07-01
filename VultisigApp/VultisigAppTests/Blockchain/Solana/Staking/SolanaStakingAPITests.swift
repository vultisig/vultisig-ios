//
//  SolanaStakingAPITests.swift
//  VultisigAppTests
//
//  Pins the JSON-RPC envelope + the stake-filtered getProgramAccounts shape
//  (dataSize:200 + memcmp{offset:12, bytes:owner} + dataSlice for pubkey-only).
//  These params are the contract with the RPC node, so they're asserted
//  structurally rather than by golden string.
//

@testable import VultisigApp
import XCTest

final class SolanaStakingAPITests: XCTestCase {

    private let owner = "5S2YKfAvT5r3NGmreYUqAskXFygNnmGsEu78hX9fGJg9"

    private func params(for method: SolanaAPI.Method) throws -> [String: Any] {
        let api = SolanaAPI(baseURL: SolanaAPI.rpcBaseURL, usesProxyPath: true, rpcMethod: method)
        guard case .requestParameters(let envelope, _) = api.task else {
            XCTFail("expected requestParameters task")
            return [:]
        }
        return envelope
    }

    func testStakeAccountsByOwnerJsonParsedFilterShape() throws {
        let envelope = try params(for: .getStakeAccountsByOwner(staker: owner, pubkeyOnly: false))

        XCTAssertEqual(envelope["method"] as? String, "getProgramAccounts")
        let rpcParams = try XCTUnwrap(envelope["params"] as? [Any])
        XCTAssertEqual(rpcParams.first as? String, SolanaStakingConfig.stakeProgramId)

        let config = try XCTUnwrap(rpcParams[1] as? [String: Any])
        XCTAssertEqual(config["encoding"] as? String, "jsonParsed")

        let filters = try XCTUnwrap(config["filters"] as? [[String: Any]])
        XCTAssertEqual(filters.count, 2)

        let dataSizeFilter = try XCTUnwrap(filters.first { $0["dataSize"] != nil })
        XCTAssertEqual(dataSizeFilter["dataSize"] as? Int, 200)

        let memcmpFilter = try XCTUnwrap(filters.first { $0["memcmp"] != nil })
        let memcmp = try XCTUnwrap(memcmpFilter["memcmp"] as? [String: Any])
        XCTAssertEqual(memcmp["offset"] as? Int, 12)
        XCTAssertEqual(memcmp["bytes"] as? String, owner)
    }

    func testStakeAccountsByOwnerPubkeyOnlyUsesZeroLengthDataSlice() throws {
        let envelope = try params(for: .getStakeAccountsByOwner(staker: owner, pubkeyOnly: true))
        let rpcParams = try XCTUnwrap(envelope["params"] as? [Any])
        let config = try XCTUnwrap(rpcParams[1] as? [String: Any])

        XCTAssertEqual(config["encoding"] as? String, "base64")
        let dataSlice = try XCTUnwrap(config["dataSlice"] as? [String: Any])
        XCTAssertEqual(dataSlice["offset"] as? Int, 0)
        XCTAssertEqual(dataSlice["length"] as? Int, 0)
        // The dataSize:200 + owner memcmp filters must still be present so the
        // zero-length slice doesn't widen the scan beyond stake-state accounts.
        let filters = try XCTUnwrap(config["filters"] as? [[String: Any]])
        XCTAssertTrue(filters.contains { $0["dataSize"] as? Int == 200 })
        XCTAssertTrue(filters.contains { ($0["memcmp"] as? [String: Any])?["bytes"] as? String == owner })
    }

    func testMinimumBalanceForRentExemptionParam() throws {
        let envelope = try params(for: .getMinimumBalanceForRentExemption(size: 200))
        XCTAssertEqual(envelope["method"] as? String, "getMinimumBalanceForRentExemption")
        let rpcParams = try XCTUnwrap(envelope["params"] as? [Any])
        XCTAssertEqual(rpcParams.first as? Int, 200)
    }

    func testEpochInfoMethod() throws {
        let envelope = try params(for: .getEpochInfo)
        XCTAssertEqual(envelope["method"] as? String, "getEpochInfo")
    }

    func testVoteAccountsMethod() throws {
        let envelope = try params(for: .getVoteAccounts)
        XCTAssertEqual(envelope["method"] as? String, "getVoteAccounts")
    }

    func testStakeMinimumDelegationMethodTakesNoParams() throws {
        let envelope = try params(for: .getStakeMinimumDelegation)
        XCTAssertEqual(envelope["method"] as? String, "getStakeMinimumDelegation")
        let rpcParams = try XCTUnwrap(envelope["params"] as? [Any])
        XCTAssertTrue(rpcParams.isEmpty)
    }

    func testMinDelegationPublicHostsDropTheProxyPath() {
        // The public endpoints are complete JSON-RPC URLs, so the `/solana/`
        // proxy path must not be appended.
        for host in SolanaAPI.minDelegationPublicHosts {
            let api = SolanaAPI(baseURL: host, usesProxyPath: false, rpcMethod: .getStakeMinimumDelegation)
            XCTAssertEqual(api.path, "")
        }
        XCTAssertFalse(SolanaAPI.minDelegationPublicHosts.isEmpty)
    }

    // MARK: - Response decoding

    func testEpochInfoResponseDecodes() throws {
        let json = """
        { "result": { "absoluteSlot": 429032115, "blockHeight": 407107405, "epoch": 993, "slotIndex": 56115, "slotsInEpoch": 432000, "transactionCount": 523987433358 } }
        """
        let response = try JSONDecoder().decode(SolanaGetEpochInfoResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.result.epoch, 993)
        XCTAssertEqual(response.result.slotsInEpoch, 432_000)
        XCTAssertEqual(response.result.slotIndex, 56_115)
    }

    func testRentExemptionResponseDecodes() throws {
        let response = try JSONDecoder().decode(
            SolanaGetMinimumBalanceForRentExemptionResponse.self,
            from: Data(#"{ "result": 2282880 }"#.utf8)
        )
        XCTAssertEqual(response.result, 2_282_880)
    }

    func testStakeMinimumDelegationResponseDecodes() throws {
        // Shape returned by public nodes: `result` wraps `context` + `value`.
        let json = #"{ "jsonrpc": "2.0", "result": { "context": { "slot": 429993219 }, "value": 1000000000 }, "id": 1 }"#
        let response = try JSONDecoder().decode(
            SolanaGetStakeMinimumDelegationResponse.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(response.result.value, 1_000_000_000)
    }

    func testVoteAccountsResponseDecodesAndTagsDelinquency() throws {
        let json = """
        {
          "result": {
            "current": [
              { "votePubkey": "VoteA", "nodePubkey": "NodeA", "activatedStake": 191497989337835, "commission": 0, "epochVoteAccount": true, "lastVote": 1, "rootSlot": 1 }
            ],
            "delinquent": [
              { "votePubkey": "VoteB", "nodePubkey": "NodeB", "activatedStake": 5, "commission": 100, "epochVoteAccount": false, "lastVote": 1, "rootSlot": 1 }
            ]
          }
        }
        """
        let response = try JSONDecoder().decode(SolanaGetVoteAccountsResponse.self, from: Data(json.utf8))
        let current = response.result.current.map { SolanaValidator(voteAccount: $0, isDelinquent: false) }
        let delinquent = response.result.delinquent.map { SolanaValidator(voteAccount: $0, isDelinquent: true) }

        XCTAssertEqual(current.first?.votePubkey, "VoteA")
        XCTAssertEqual(current.first?.activatedStake, 191_497_989_337_835)
        XCTAssertFalse(current.first?.isDelinquent ?? true)
        XCTAssertTrue(delinquent.first?.isDelinquent ?? false)
        XCTAssertEqual(delinquent.first?.commission, 100)
        // Metadata starts empty (enrichment lands in a later PR).
        XCTAssertNil(current.first?.metadata.name)
    }
}
